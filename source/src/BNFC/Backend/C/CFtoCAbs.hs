{-
    BNF Converter: C Abstract syntax
    Copyright (C) 2004  Author:  Michael Pellauer

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{-
   **************************************************************
    BNF Converter Module

    Description   : This module generates the C Abstract Syntax
                    tree classes. It generates both a Header file
                    and an Implementation file, and Appel's C
                    method.

    Author        : Michael Pellauer (pellauer@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 15 September, 2003

    Modified      : 15 September, 2003


   **************************************************************
-}

module BNFC.Backend.C.CFtoCAbs (cf2CAbs) where

import BNFC.CF
import BNFC.Utils((+++),(++++))
import BNFC.Backend.Common.NamedVariables
import Data.List
import Data.Char(toLower)


--The result is two files (.H file, .C file)
cf2CAbs :: String -> CF -> (String, String)
cf2CAbs name cf = (mkHFile cf, mkCFile cf)


{- **** Header (.H) File Functions **** -}

--Makes the Header file.
mkHFile :: CF -> String
mkHFile cf = unlines
 [
  "#ifndef ABSYN_HEADER",
  "#define ABSYN_HEADER",
  "",
  header,
  prTypeDefs user,
  "/********************   Forward Declarations    ********************/\n",
  concatMap prForward classes,
  "",
  "/********************   Abstract Syntax Classes    ********************/\n",
  concatMap (prDataH user) (cf2dataLists cf),
  "",
  "#endif"
 ]
 where
  user = fst (unzip (tokenPragmas cf))
  header = "/* C++ Abstract Syntax Interface generated by the BNF Converter.*/\n"
  rules = getRules cf
  classes = rules ++ getClasses (allCats cf)
  prForward s | not (isCoercion s) = unlines
    [
     "struct " ++ s' ++ "_;",
     "typedef struct " ++ s' ++ "_ *" ++ s' ++ ";"
    ]
   where
    s' = normCat s
  prForward s = ""
  getRules cf = (map testRule (rulesOfCF cf))
  getClasses [] = []
  getClasses (c:cs) =
   if identCat (normCat c) /= c
   then getClasses cs
   else if elem c rules
     then getClasses cs
     else c : (getClasses cs)

  testRule (Rule f c r) =
   if isList c
   then if isConsFun f
     then identCat c
     else "_" --ignore this
   else "_"

--Prints struct definitions for all categories.
prDataH :: [UserDef] -> Data -> String
prDataH user (cat, rules) =
   if isList cat
      then unlines
       [
        "struct " ++ c' ++ "_",
        "{",
        "  " ++ mem +++ (varName mem) ++ ";",
        "  " ++ c' +++ (varName c') ++ ";",
        "};",
        "",
        c' ++ " make_" ++ c' ++ "(" ++ mem ++ " p1, " ++ c' ++ " p2);"
       ]
      else unlines
       [
        "struct " ++ cat ++ "_",
        "{",
        "  enum { " ++ (concat (intersperse ", " (map prKind rules))) ++ " } kind;",
        "  union",
        "  {",
        concatMap (prUnion user) rules ++ "  } u;",
        "};",
        "",
        concatMap (prRuleH user cat) rules
       ]
 where
  c' = identCat (normCat cat)
  mem = identCat (normCatOfList cat)
  prKind (fun, cats) = "is_" ++ (normCat fun)
  prMember user (fun, []) = ""
  prMember user (fun, cats) = "  " ++ (prInstVars user (getVars cats))
  prUnion user (fun, []) = ""
  prUnion user (fun, cats) = "    struct { " ++ (prInstVars user (getVars cats)) ++ " } " ++ (memName fun) ++ ";\n"


--Interface definitions for rules vary on the type of rule.
prRuleH :: [UserDef] -> String -> (Fun, [Cat]) -> String
prRuleH user c (fun, cats) =
    if isNilFun fun || isOneFun fun || isConsFun fun
    then ""  --these are not represented in the AbSyn
    else --a standard rule
      c ++ " make_" ++ fun' ++ "(" ++ (prParamsH 0 (getVars cats)) ++ ");\n"
   where
     fun' = identCat (normCat fun)
     prParamsH :: Int -> [(String, a)] -> String
     prParamsH _ [] = ""
     prParamsH n ((t,_):[]) = t ++ " p" ++ (show n)
     prParamsH n ((t,_):vs) = (t ++ " p" ++ (show n) ++ ", ") ++ (prParamsH (n+1) vs)

--typedefs in the Header make generation much nicer.
prTypeDefs user = unlines
  [
   "/********************   TypeDef Section    ********************/",
   "typedef int Integer;",
   "typedef char Char;",
   "typedef double Double;",
   "typedef char* String;",
   "typedef char* Ident;",
   concatMap prUserDef user
  ]
 where
  prUserDef s = "typedef char* " ++ s ++ ";\n"

--A class's instance variables.
prInstVars :: [UserDef] -> [IVar] -> String
prInstVars _ [] = []
prInstVars user vars@((t,n):[]) =
  t +++ uniques
 where
   (uniques, vs') = prUniques t vars
prInstVars user vars@((t,n):vs) =
  t +++ uniques ++
  (prInstVars user vs')
 where
   (uniques, vs') = prUniques t vars

--these functions group the types together nicely
prUniques :: String -> [IVar] -> (String, [IVar])
prUniques t vs = (prVars (findIndices (\x -> case x of (y,_) ->  y == t) vs) vs, remType t vs)
 where
   remType :: String -> [IVar] -> [IVar]
   remType _ [] = []
   remType t ((t2,n):ts) = if t == t2
   				then (remType t ts)
				else (t2,n) : (remType t ts)
   prVars (x:[]) vs =  case vs !! x of
   			(t,n) -> (varName t) ++ (showNum n) ++ ";"
   prVars (x:xs) vs = case vs !! x of
   			(t,n) -> (varName t) ++ (showNum n) ++ ", " ++
				 (prVars xs vs)


{- **** Implementation (.C) File Functions **** -}

--Makes the .C file
mkCFile :: CF -> String
mkCFile cf = unlines
 [
  header,
  concatMap (prDataC user) (cf2dataLists cf)
 ]
 where
  user = fst (unzip (tokenPragmas cf))
  header = unlines
   [
    "/* C Abstract Syntax Implementation generated by the BNF Converter. */",
    "",
    "#include <stdio.h>",
    "#include <stdlib.h>",
    "#include \"Absyn.h\"",
    ""
   ]

--This is not represented in the implementation.
--This is not represented in the implementation.
prDataC :: [UserDef] -> Data -> String
prDataC user (cat, rules) = concatMap (prRuleC user cat) rules

--Classes for rules vary based on the type of rule.
prRuleC user c (fun, cats) =
    if isNilFun fun || isOneFun fun
    then ""  --these are not represented in the AbSyn
    else if isConsFun fun
    then --this is the linked list case.
    unlines
    [
     "/********************   " ++ c' ++ "    ********************/",
     prListFuncs user c',
     ""
    ]
    else --a standard rule
    unlines
    [
     "/********************   " ++ fun' ++ "    ********************/",
     prConstructorC user c fun' vs cats,
     ""
    ]
   where
     vs = getVars cats
     fun' = identCat (normCat fun)
     c' = identCat (normCat c)

--These are all built-in list functions.
--Later we could include things like lookup,insert,delete,etc.
prListFuncs :: [UserDef] -> String -> String
prListFuncs user c = unlines
 [
   c ++ " make_" ++ c ++"(" ++ m ++ " p1" ++ ", " ++ c ++ " p2)",
   "{",
   "  " ++ c ++ " tmp = (" ++ c ++ ") malloc(sizeof(*tmp));",
   "  if (!tmp)",
   "  {",
   "    fprintf(stderr, \"Error: out of memory when allocating " ++ c ++ "!\\n\");",
   "    exit(1);",
   "  }",
   "  tmp->" ++ m' ++ " = " ++ "p1;",
   "  tmp->" ++ v ++ " = " ++ "p2;",
   "  return tmp;",
   "}"
 ]
 where
   v = (map toLower c) ++ "_"
   m = drop 4 c
   m' = drop 4 v

--The constructor just assigns the parameters to the corresponding instance variables.
prConstructorC :: [UserDef] -> String -> String -> [IVar] -> [Cat] -> String
prConstructorC user cat c vs cats =
  unlines
  [
   cat' ++ " make_" ++ c ++"(" ++ (interleave types params) ++ ")",
   "{",
   "  " ++ cat' ++ " tmp = (" ++ cat' ++ ") malloc(sizeof(*tmp));",
   "  if (!tmp)",
   "  {",
   "    fprintf(stderr, \"Error: out of memory when allocating " ++ c ++ "!\\n\");",
   "    exit(1);",
   "  }",
   "  tmp->kind = is_" ++ c ++ ";",
   prAssigns c vs params,
   "  return tmp;",
   "}"
  ]
 where
   cat' = identCat (normCat cat)
   (types, params) = unzip (prParams cats (length cats) ((length cats)+1))
   interleave _ [] = []
   interleave (x:[]) (y:[]) = x +++ y
   interleave (x:xs) (y:ys) = x +++ y ++ "," +++ (interleave xs ys)

--Prints the constructor's parameters.
prParams :: [Cat] -> Int -> Int -> [(String,String)]
prParams [] _ _ = []
prParams (c:cs) n m = (identCat c,"p" ++ (show (m-n)))
			: (prParams cs (n-1) m)

--Prints the assignments of parameters to instance variables.
--This algorithm peeks ahead in the list so we don't use map or fold
prAssigns :: String -> [IVar] -> [String] -> String
prAssigns _ [] _ = []
prAssigns _ _ [] = []
prAssigns c ((t,n):vs) (p:ps) =
  if n == 1 then
   case findIndices (\x -> case x of (l,r) -> l == t) vs of
    [] -> "  tmp->u." ++ c' ++ "_." ++ (varName t) ++ " = " ++ p ++ ";\n" ++ (prAssigns c vs ps)
    z -> "  tmp->u." ++ c' ++ "_." ++ ((varName t) ++ (showNum n)) ++ " = " ++ p ++ ";\n" ++ (prAssigns c vs ps)
  else "  tmp->u." ++ c' ++ "_." ++ ((varName t) ++ (showNum n)) ++ " = " ++ p ++ ";\n" ++ (prAssigns c vs ps)
 where
  c' = map toLower c

{- **** Helper Functions **** -}

--Checks if something is a basic or user-defined type.
isBasic :: [UserDef] -> String -> Bool
isBasic user x =
  if elem x user
    then True
    else case x of
      "Integer" -> True
      "Char" -> True
      "String" -> True
      "Double" -> True
      "Ident" -> True
      _ -> False

memName s = (map toLower s) ++ "_"
