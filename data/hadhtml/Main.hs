
module Main where

import System
import Directory
import List

import Lexer
import TextUtil
import Char


copyright = ["-- Generated by Hoogle, from Haddock HTML", "-- (C) Neil Mitchell 2005",""]


-- example, for full GHC do C:\ghc\ghc-6.4\doc\html\libraries
main = do xs <- getArgs
          let res = case xs of
                (a:_) -> a
                [] -> "C:\\ghc\\ghc-6.4.1\\doc\\html\\libraries"
          hoogledoc res


test = hoogledoc "examples"





hoogledoc :: FilePath -> IO ()
hoogledoc x = do filelist <- docFiles x
                 textlist <- mapM readFile filelist
                 
                 excludeExists <- doesFileExist "exclude.txt"
                 excludeSrc <- if excludeExists then readFile "exclude.txt" else return ""
                 prefix <- readFile "prefix.txt"
                 h98 <- loadH98
                 
                 let filetext = zip filelist textlist
                     exclude = lines excludeSrc
                     results = onlyOnce $ h98 ++ concatMap (uncurry (document exclude)) filetext
                 writeFile "hoogle-ghc.txt" $ unlines (copyright ++ lines prefix ++ results)


-- load up the libraries that GHC shows distain for...
loadH98 :: IO [(String, [String])]
loadH98 =  do x <- readFile "haskell98.txt"
              return $ f $ filter (not . null) $ lines x
    where
        f [] = []
        f (x:xs) = (drop 7 x,a) : f b
            where (a,b) = break ("module" `isPrefixOf`) xs


onlyOnce :: [(String, [String])] -> [String] 
onlyOnce xs = concatMap g ordered
    where
        ordered = groupBy eqFst $ sortBy cmpFst items
        items = map f $ groupBy eqSnd $ sortBy cmpSnd $ concatMap (\(a,b) -> map ((,) a) b) xs
        
        eqSnd  (_,a) (_,b) = a == b
        cmpSnd (_,a) (_,b) = a `compare` b
        eqFst  (a,_) (b,_) = a == b
        cmpFst (a,_) (b,_) = a `compare` b
        
        modFst (a,_) (b,_) = length (filter (== '.') a) `compare` length (filter (== '.') b)
        
        f xs = head $ sortBy modFst xs
        g xs@((name,_):_) = ["", "module " ++ name] ++ map snd xs
        
        

{-
doctest x = do let file = "C:/ghc/ghc-6.4/doc/html/libraries/parsec/Text.ParserCombinators.Parsec" ++ x ++ ".html"
               src <- readFile file
               let y = unlines $ document [] file src
               writeFile "result.txt" y
-}


-- the entries to output
document :: [String] -> FilePath -> String -> [(String, [String])]
document exclude file contents = 
        if hide then []
        else if any isSpace name then []
        else [(name, rewrite lexs)]
    where
        hide = any (`isPrefixOf` name) (map init partial) || any (== name) full
        (partial, full) = partition (\x -> last x == '.') exclude
    
        lexs = lexer contents
        name = modName lexs



data Flags = IsDir | IsHtml | IsNone
             deriving (Show, Eq)


docFiles :: FilePath -> IO [FilePath]
docFiles x = do xFlag <- getFlag x
                if xFlag == IsHtml then return [x] else do
                dir <- getDirectoryContents x
                let qdir = map (\y -> x ++ "/" ++ y) (filter (\x -> head x /= '.') dir)
                flags <- mapM getFlag qdir
                let flag_dir = zip flags qdir
                    resdirs = map snd $ filter (\(a,b) -> a == IsDir ) flag_dir
                    reshtml = map snd $ filter (\(a,b) -> a == IsHtml) flag_dir
                children <- mapM docFiles resdirs
                return $ reshtml ++ concat children
    where
        getFlag ('.':_) = return IsNone
        getFlag xs | ".html" `isSuffixOf` xs = return IsHtml
        getFlag x = do y <- doesDirectoryExist x
                       return $ if y then IsDir else IsNone



---- REWRITER

getAttr :: Lexeme -> String -> String
getAttr (Tag _ attr) name =
    case lookup name attr of
        Nothing -> ""
        Just x -> x
        
        
rewrite = concatMap rejoin . bundle . map deForall . extract
        

rebundle = bundle . map tail


deForall :: String -> String
deForall x = g x
    where
        g x | "forall " `isPrefixOf` x = g $ noImp $ tail $ tail $ dropWhile (/= '.') x
        g (x:xs) = x : g xs
        g [] = []
        
        noImp x = f x
            where
                f ('=':'>':' ':xs) = xs
                f (x:xs) = f xs
                f [] = x
        


bundle :: [String] -> [[String]]
bundle (x:xs) = (x:a) : bundle b
    where (a,b) = break (not . isSpace . head) xs
bundle [] = []

        
rejoin :: [String] -> [String]
rejoin [x] = [x]
rejoin (x:xs) | "data " `isPrefixOf` x || "newtype " `isPrefixOf` x = rejoinData (x:xs)
rejoin (x:xs) | "class " `isPrefixOf` trim x = rejoinClass (x:xs)
rejoin (x:xs) = [concat (x:map ((++) " " . tail) xs)]


rejoinData (dat:xs) = nub $ (keyword ++ " " ++ pre) : (concatMap f $ rebundle xs)
    where
        (keyword, _:pre) = break (== ' ') dat
        
        f ("Instances":xs) = map ((++) "instance " . tail) xs
        f ("Constructors":xs) = concatMap g $ rebundle xs
        
        g [x] = [y ++ " :: " ++ concatMap (++ " -> ") ys ++ pre]
            where (y:ys) = chunks x
            
        g (x:xs) = (dechunk $ x : "::" : concatMap h xs ++ [pre]) : concatMap t xs
        
        h x = res
            where
                res = concatMap (++ ["->"]) (replicate (reps+1) typ2)
            
                reps = length $ filter (== ',') names
                (names:_:typ) = chunks x
                typ2 = bracketStrip typ
        
        t x = map res names
            where
                names = splitList "," a
                res name = dechunk $ name : "::" : clls ++ pre : "->" : imp
                
                (a:_:b) = chunks x
                bb = bracketStrip b
                (cls,rest) = break (== "=>") bb
                
                clls = if null rest then [] else cls ++ ["=>"]
                imp = if null rest then cls else tail rest


bracketStrip ['(':xs] | not ('(' `elem` xs) = chunks $ init xs
bracketStrip x = x
                


rejoinClass (dat:xs) = ("class " ++ pre) : (concatMap f $ rebundle xs)
    where
        pre2 = drop 6 $ reverse $ drop 7 $ reverse dat
        pre = if '|' `elem` pre2 then takeWhile (/= '|') pre2 else pre2
        
        cpre = chunks pre
        body = dechunk $
            if "=>" `elem` cpre then tail (dropWhile (/= "=>") cpre) else cpre
        
        f ("Instances":xs) = []
        f ("Methods":xs) = map g $ rebundle xs
        f (x:xs) = error $ "rejoinClass: " ++ x
        
        g [x] = dechunk $ a ++ "::" : cls : "=>" : imp
            where
                (a,b2) = break (== "::") (chunks x)
                b = if null b2 then error pre else tail b2
                (c,d) = break (== "=>") b
                
                cls = if null d then body else concat ["(", body, ", ", nobrackets (dechunk c), ")"]
                imp = if null d then b else tail d
                
                nobrackets ('(':xs) = init xs
                nobrackets x = x
        
        g xs = g [dechunk xs]


dechunk = concat . intersperse " "

-- divide up into lexemes, respecting brackets
chunks :: String -> [String]
chunks x = filter (not . null) $ f "" 0 x
    where
        f a n (',':' ':xs) = f a n (',':xs)
        f a n (x:xs) | x `elem` "[({" = f (x:a) (n+1) xs
                     | x `elem` "])}" = f (x:a) (n-1) xs
                     | isSpace x && n == 0 = reverse a : f "" n xs
                     | otherwise = f (x:a) n xs
        f a n [] = [reverse a]



extract :: [Lexeme] -> [String]
extract xs =
        filter (not . isPrefixOf "module") $ -- remove modules
        dropWhile (isSpace . head) $     -- remove synopsis
        f (-1) xs
    where
        f n (Tag "TABLE" _:xs) = f (n+1) xs
        f n (ShutTag "TABLE":xs) = f (n-1) xs
        f n [] = []
        
        f n (t@(Tag "TD" attr):xs) | att `elem` ["decl","arg","section4"] = g n "" xs
            where att = getAttr t "CLASS"
        f n (_:xs) = f n xs
        
        g n a (Tag "TABLE" _:xs) = h n 1 a xs
        g n a (ShutTag "TD":xs) = (replicate n '\t' ++ trim a) : f n xs
        g n a (Text x:xs) = g n (a ++ x) xs
        g n a (_:xs) = g n a xs
        
        h n m a (Text x:xs) = h n m (a ++ x) xs
        h n m a (ShutTag "TABLE":xs) = if m == 1 then g n a xs else h n (m-1) a xs
        h n m a (Tag "TABLE" _:xs) = h n (m+1) a xs
        h n m a (_:xs) = h n m a xs


deescape ('&':'g':'t':';':xs) = '>' : deescape xs
deescape ('&':'l':'t':';':xs) = '<' : deescape xs
deescape ('&':'a':'m':'p':';':xs) = '&' : deescape xs
deescape (x:xs) = x : deescape xs
deescape [] = []



modName :: [Lexeme] -> String
modName x = a
    where Text a = head $ tail $ dropWhile (isntTag $ Tag "TITLE" []) $ x


-- first one is the pattern, second is the actual
isTag :: Lexeme -> Lexeme -> Bool
isTag (Tag a c) (Tag b d) = eqEmpty a b && all contain c
    where contain (key, val) = Just val == lookup key d

isTag (ShutTag a) (ShutTag b) = eqEmpty a b
isTag (Text a) (Text b) = eqEmpty a b
isTag _ _ = False

isntTag a b = not (isTag a b)

eqEmpty a b = a == "" || a == b

