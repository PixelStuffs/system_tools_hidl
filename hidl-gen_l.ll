/*
 * Copyright (C) 2016 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

D                   [0-9]
L                   [a-zA-Z_]
H                   [a-fA-F0-9]
E                   [Ee][+-]?{D}+
FS                  (f|F|l|L)
IS                  (u|U|l|L)*

COMPONENT           {L}({L}|{D})*
DOT                 [.]
AT                  [@]
VERSION             {AT}{D}+{DOT}{D}+
FQNAME              ({COMPONENT}|{VERSION})(({DOT}|":"+){COMPONENT}|{VERSION})*

%{

#include "Annotation.h"
#include "AST.h"
#include "ArrayType.h"
#include "CompoundType.h"
#include "ConstantExpression.h"
#include "DeathRecipientType.h"
#include "DocComment.h"
#include "EnumType.h"
#include "HandleType.h"
#include "MemoryType.h"
#include "Method.h"
#include "PointerType.h"
#include "ScalarType.h"
#include "Scope.h"
#include "StringType.h"
#include "VectorType.h"
#include "FmqType.h"

#include "hidl-gen_y-helpers.h"

#include <assert.h>
#include <algorithm>
#include <hidl-util/StringHelper.h>

using namespace android;
using token = yy::parser::token;

#define SCALAR_TYPE(kind)                                        \
    {                                                            \
        yylval->type = new ScalarType(ScalarType::kind, *scope); \
        return token::TYPE;                                      \
    }

#define YY_DECL int yylex(YYSTYPE* yylval_param, YYLTYPE* yylloc_param,  \
    yyscan_t yyscanner, android::AST* const ast, android::Scope** const scope)

#ifndef YYSTYPE
#define YYSTYPE yy::parser::semantic_type
#endif

#ifndef YYLTYPE
#define YYLTYPE yy::parser::location_type
#endif

#define YY_USER_ACTION yylloc->step(); yylloc->columns(yyleng);

%}

%option yylineno
%option noyywrap
%option nounput
%option noinput
%option reentrant
%option bison-bridge
%option bison-locations

%%

\/\*([^*]|\*+[^*\/])*\*+\/  {
                                std::string str(yytext);

                                // Add the lines to location (to keep it updated)
                                yylloc->lines(std::count(str.begin(), str.end(), '\n'));

                                str = StringHelper::LTrim(str, "/");
                                bool isDoc = StringHelper::StartsWith(str, "**");
                                str = StringHelper::LTrimAll(str, "*");
                                str = StringHelper::RTrim(str, "/");
                                str = StringHelper::RTrimAll(str, "*");

                                yylval->str = strdup(str.c_str());
                                return isDoc ? token::DOC_COMMENT : token::MULTILINE_COMMENT;
                            }

"//"[^\r\n]*        {
                        ast->addUnhandledComment(
                                new DocComment(yytext,
                                               convertYYLoc(*yylloc, ast),
                                               CommentType::SINGLELINE));
                    }

"enum"              { return token::ENUM; }
"extends"           { return token::EXTENDS; }
"generates"         { return token::GENERATES; }
"import"            { return token::IMPORT; }
"interface"         { return token::INTERFACE; }
"package"           { return token::PACKAGE; }
"safe_union"        { return token::SAFE_UNION; }
"struct"            { return token::STRUCT; }
"typedef"           { return token::TYPEDEF; }
"union"             { return token::UNION; }
"bitfield"          { yylval->templatedType = new BitFieldType(*scope); return token::TEMPLATED; }
"vec"               { yylval->templatedType = new VectorType(*scope); return token::TEMPLATED; }
"oneway"            { return token::ONEWAY; }

"bool"              { SCALAR_TYPE(KIND_BOOL); }
"int8_t"            { SCALAR_TYPE(KIND_INT8); }
"uint8_t"           { SCALAR_TYPE(KIND_UINT8); }
"int16_t"           { SCALAR_TYPE(KIND_INT16); }
"uint16_t"          { SCALAR_TYPE(KIND_UINT16); }
"int32_t"           { SCALAR_TYPE(KIND_INT32); }
"uint32_t"          { SCALAR_TYPE(KIND_UINT32); }
"int64_t"           { SCALAR_TYPE(KIND_INT64); }
"uint64_t"          { SCALAR_TYPE(KIND_UINT64); }
"float"             { SCALAR_TYPE(KIND_FLOAT); }
"double"            { SCALAR_TYPE(KIND_DOUBLE); }

"death_recipient"   { yylval->type = new DeathRecipientType(*scope); return token::TYPE; }
"handle"            { yylval->type = new HandleType(*scope); return token::TYPE; }
"memory"            { yylval->type = new MemoryType(*scope); return token::TYPE; }
"pointer"           { yylval->type = new PointerType(*scope); return token::TYPE; }
"string"            { yylval->type = new StringType(*scope); return token::TYPE; }

"fmq_sync"          { yylval->type = new FmqType("::android::hardware", "MQDescriptorSync", *scope, "fmq_sync"); return token::TEMPLATED; }
"fmq_unsync"        { yylval->type = new FmqType("::android::hardware", "MQDescriptorUnsync", *scope, "fmq_unsync"); return token::TEMPLATED; }

"("                 { return('('); }
")"                 { return(')'); }
"<"                 { return('<'); }
">"                 { return('>'); }
"{"                 { return('{'); }
"}"                 { return('}'); }
"["                 { return('['); }
"]"                 { return(']'); }
":"                 { return(':'); }
";"                 { return(';'); }
","                 { return(','); }
"."                 { return('.'); }
"="                 { return('='); }
"+"                 { return('+'); }
"-"                 { return('-'); }
"*"                 { return('*'); }
"/"                 { return('/'); }
"%"                 { return('%'); }
"&"                 { return('&'); }
"|"                 { return('|'); }
"^"                 { return('^'); }
"<<"                { return(token::LSHIFT); }
">>"                { return(token::RSHIFT); }
"&&"                { return(token::LOGICAL_AND); }
"||"                { return(token::LOGICAL_OR);  }
"!"                 { return('!'); }
"~"                 { return('~'); }
"<="                { return(token::LEQ); }
">="                { return(token::GEQ); }
"=="                { return(token::EQUALITY); }
"!="                { return(token::NEQ); }
"?"                 { return('?'); }
"@"                 { return('@'); }
"#"                 { return('#'); }

{COMPONENT}         { yylval->str = strdup(yytext); return token::IDENTIFIER; }
{FQNAME}            { yylval->str = strdup(yytext); return token::FQNAME; }

0[xX]{H}+{IS}?      { yylval->str = strdup(yytext); return token::INTEGER; }
0{D}+{IS}?          { yylval->str = strdup(yytext); return token::INTEGER; }
{D}+{IS}?           { yylval->str = strdup(yytext); return token::INTEGER; }
L?\"(\\.|[^\\"])*\" { yylval->str = strdup(yytext); return token::STRING_LITERAL; }

{D}+{E}{FS}?        { yylval->str = strdup(yytext); return token::FLOAT; }
{D}+\.{E}?{FS}?     { yylval->str = strdup(yytext); return token::FLOAT; }
{D}*\.{D}+{E}?{FS}? { yylval->str = strdup(yytext); return token::FLOAT; }

\n|\r\n             { yylloc->lines(); }
[ \t\f\v]           { /* ignore all other whitespace */ }

.                   { yylval->str = strdup(yytext); return token::UNKNOWN; }

%%

namespace android {

status_t parseFile(AST* ast, std::unique_ptr<FILE, std::function<void(FILE *)>> file) {
    yyscan_t scanner;
    yylex_init(&scanner);

    yyset_in(file.get(), scanner);

    Scope* scopeStack = ast->getMutableRootScope();
    int res = yy::parser(scanner, ast, &scopeStack).parse();

    yylex_destroy(scanner);

    if (res != 0 || ast->syntaxErrors() != 0) {
        return UNKNOWN_ERROR;
    }

    return OK;
}

}  // namespace android
