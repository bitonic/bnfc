{-
    BNF Converter: Java 1.5 Abstract Syntax
    Copyright (C) 2004  Author:  Michael Pellauer, Bjorn Bringert

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

    Description   : This module generates the Java Abstract Syntax
                    It uses the BNFC.Backend.Common.NamedVariables module for variable
                    naming. It returns a list of file names, and the
                    contents to be written into that file. (In Java
                    public classes must go in their own file.)

                    The generated classes also support the Visitor
                    Design Pattern.

    Author        : Michael Pellauer (pellauer@cs.chalmers.se),
                    Bjorn Bringert (bringert@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 24 April, 2003

    Modified      : 16 June, 2004


   **************************************************************
-}

module BNFC.Backend.Java.CFtoJavaAbs15 (cf2JavaAbs, typename) where

import BNFC.CF
import BNFC.Utils((+++),(++++))
import BNFC.Backend.Common.NamedVariables hiding (IVar, getVars, varName)
import Data.List
import Data.Char(toLower, isDigit)
import Data.Maybe(catMaybes,fromMaybe)

--Produces abstract data types in Java.
--These follow Appel's "non-object oriented" version.
--They also allow users to use the Visitor design pattern.

type IVar = (String, Int, Maybe String)
--The type of an instance variable
--a # unique to that type
--and an optional name (handles typedefs).

--The result is a list of files which must be written to disk.
--The tuple is (FileName, FileContents)
cf2JavaAbs :: String -> String -> CF -> [(FilePath, String)]
cf2JavaAbs packageBase packageAbsyn cf =
    concatMap (prData header packageAbsyn user) rules
 where
  header = "package " ++ packageAbsyn ++ "; // Java Package generated by the BNF Converter.\n"
  user = [n | (n,_) <- tokenPragmas cf]
  rules = [ (normCat c,fs) | (c,fs) <- cf2dataLists cf]

--Generates a (possibly abstract) category class, and classes for all its rules.
prData :: String -> String -> [UserDef] -> Data ->[(String, String)]
prData header packageAbsyn user (cat, rules) =
  categoryClass ++ (catMaybes $ map (prRule header packageAbsyn funs user cat) rules)
      where
      funs = map fst rules
      categoryClass
	  | cat `elem` funs = [] -- the catgory is also a function, skip abstract class
	  | otherwise = [(identCat cat, header ++++
			 unlines [
				  "public abstract class" +++ cls
                                    +++ "implements java.io.Serializable {",
				  "  public abstract <R,A> R accept("
				  ++ cls ++ ".Visitor<R,A> v, A arg);",
				  prVisitor packageAbsyn funs,
				  "}"
				 ])]
                where cls = identCat cat

prVisitor :: String -> [String] -> String
prVisitor packageAbsyn funs =
    unlines [
	     "  public interface Visitor <R,A> {",
	     unlines (map prVisitFun funs),
	     "  }"
	    ]
    where
    prVisitFun f = "    public R visit(" ++ packageAbsyn ++ "." ++ f ++ " p, A arg);"

--Generates classes for a rule, depending on what type of rule it is.
prRule :: String   -- ^ Header
       -> String   -- ^ Abstract syntax package name
       -> [String] -- ^ Names of all constructors in the category
       -> [UserDef] -> String -> (Fun, [Cat]) -> Maybe (String, String)
prRule h packageAbsyn funs user c (fun, cats) =
    if isNilFun fun || isOneFun fun
    then Nothing  --these are not represented in the AbSyn
    else if isConsFun fun
    then Just $ (fun', --this is the linked list case.
    unlines
    [
     h,
     "public class" +++ fun' +++ "extends java.util.LinkedList<"++ et ++"> {",
     "}"
    ])
    else Just $ (fun, --a standard rule
    unlines
    [
     h,
     "public class" +++ fun ++ ext +++ "{",
     (prInstVars vs),
     prConstructor fun user vs cats,
     prAccept packageAbsyn c fun,
     prEquals packageAbsyn fun vs,
     prHashCode packageAbsyn fun vs,
     if isAlsoCategory then prVisitor packageAbsyn funs else "",
     "}"
    ])
   where
     vs = getVars cats user
     fun' = identCat (normCat c)
     isAlsoCategory = fun == c
     --This handles the case where a LBNF label is the same as the category.
     ext = if isAlsoCategory then "" else " extends" +++ (identCat c)
     et = typename (normCatOfList c) user


--The standard accept function for the Visitor pattern
prAccept :: String -> String -> String -> String
prAccept pack cat _ = "\n  public <R,A> R accept(" ++ pack ++ "." ++ cat
		      ++ ".Visitor<R,A> v, A arg) { return v.visit(this, arg); }\n"

-- Creates the equals() method.
prEquals :: String -> String -> [IVar] -> String
prEquals pack fun vs =
    unlines $ map ("  "++) $ ["public boolean equals(Object o) {",
                              "  if (this == o) return true;",
                              "  if (o instanceof " ++ fqn ++ ") {"]
                              ++ (if null vs
                                     then ["    return true;"]
                                     else ["    " ++ fqn +++ "x = ("++fqn++")o;",
                                           "    return " ++ checkKids ++ ";"]) ++
                             ["  }",
                              "  return false;",
                              "}"]
  where
  fqn = pack++"."++fun
  checkKids = concat $ intersperse " && " $ map checkKid vs
  checkKid iv = "this." ++ v ++ ".equals(x." ++ v ++ ")"
      where v = iVarName iv

-- Creates the equals() method.
prHashCode :: String -> String -> [IVar] -> String
prHashCode pack fun vs =
    unlines $ map ("  "++) ["public int hashCode() {",
                            "  return " ++ hashKids vs ++ ";",
                            "}"
                           ]
  where
  aPrime = 37
  hashKids [] = show aPrime
  hashKids (v:vs) = hashKids_ (hashKid v) vs
  hashKids_ r [] = r
  hashKids_ r (v:vs) = hashKids_ (show aPrime ++ "*" ++ "(" ++ r ++ ")+" ++ hashKid v) vs
  hashKid iv = "this." ++ iVarName iv ++ ".hashCode()"


--A class's instance variables.
prInstVars :: [IVar] -> String
prInstVars [] = []
prInstVars vars@((t,n,nm):vs) =
  "  public" +++ "final" +++ t +++ uniques ++ ";" ++++
  (prInstVars vs')
 where
   (uniques, vs') = prUniques t vars
   --these functions group the types together nicely
   prUniques :: String -> [IVar] -> (String, [IVar])
   prUniques t vs = (prVars (findIndices (\x -> case x of (y,_,_) ->  y == t) vs) vs, remType t vs)
   prVars (x:[]) vs = iVarName (vs!!x)
   prVars (x:xs) vs = iVarName (vs!!x) ++ "," +++ prVars xs vs
   remType :: String -> [IVar] -> [IVar]
   remType _ [] = []
   remType t ((t2,n,nm):ts) = if t == t2
   				then (remType t ts)
				else (t2,n,nm) : (remType t ts)

iVarName :: IVar -> String
iVarName (t,n,nm) = varName t nm ++ showNum n

--The constructor just assigns the parameters to the corresponding instance variables.
prConstructor :: String -> [UserDef] -> [IVar] -> [Cat] -> String
prConstructor c u vs cats =
  "  public" +++ c ++"(" ++ (interleave types params) ++ ")" +++ "{" +++
   prAssigns vs params ++ "}"
  where
   (types, params) = unzip (prParams cats u (length cats) ((length cats)+1))
   interleave _ [] = []
   interleave (x:[]) (y:[]) = x +++ y
   interleave (x:xs) (y:ys) = x +++ y ++ "," +++ (interleave xs ys)

--Prints the parameters to the constructors.
prParams :: [Cat] -> [UserDef] -> Int -> Int -> [(String,String)]
prParams [] _ _ _ = []
prParams (c:cs) u n m = (identCat c',"p" ++ (show (m-n)))
			: (prParams cs u (n-1) m)
     where
      c' = typename c u

--This algorithm peeks ahead in the list so we don't use map or fold
prAssigns :: [IVar] -> [String] -> String
prAssigns [] _ = []
prAssigns _ [] = []
prAssigns ((t,n,nm):vs) (p:ps) =
 if n == 1 then
  case findIndices (\x -> case x of (l,r,_) -> l == t) vs of
    [] -> (varName t nm) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)
    z -> ((varName t nm) ++ (showNum n)) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)
 else ((varName t nm) ++ (showNum n)) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)

--Different than the standard BNFC.Backend.Common.NamedVariables version because of the user-defined
--types.
getVars :: [Cat] -> [UserDef] -> [IVar]
getVars cs user = reverse $ singleToZero $ foldl addVar [] (map identCat cs)
 where
  addVar is c = (c', n, nm):is
    where c' = typename c user
          nm = if c == c' then Nothing else Just c
          n = maximum (1:[n'+1 | (t,n',_) <- is, t == c'])
  singleToZero is = [(t,n',nm) | (t,n,nm) <- is,
                     let n' = if length (filter (hasType t) is) == 1
                               then 0 else n]
  hasType t (t',_,_) = t == t'

varName :: String -- ^ Category
	-> Maybe String -- ^ Java type name
	-> String -- ^ Variable name
varName c jt = (map toLower c') ++ "_"
 where
  c' = fromMaybe c jt

--This makes up for the fact that there's no typedef in Java
typename :: String -> [UserDef] -> String
typename t user =
 if t == "Ident"
  then "String"
  else if t == "Char"
  then "Character"
  else if elem t user
  then "String"
  else t
