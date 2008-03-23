{-# OPTIONS -fglasgow-exts #-}
module E.E(
    Id(),
    IdMap(),
    IdSet(),
    newIds,
    module E.Type,
    module E.E,
    module E.FreeVars
    ) where

import Char(chr)
import qualified Data.Traversable as T
import List
import Maybe

import E.FreeVars
import C.Prims
import Control.Monad.Identity
import E.Type
import Name.Id
import Name.Name
import Name.Names
import Name.VConsts
import Util.Gen



isWHNF ELit {} = True
isWHNF ELam {} = True
isWHNF EPi {} = True
isWHNF ESort {} = True
isWHNF ELetRec { eBody = e } = isWHNF e
isWHNF _ = False


-----------
-- E values
-----------

instance TypeNames E where
    tStar = eStar
    tInt = ELit (litCons { litName = tInt, litArgs = [], litType = eStar })
    tRational = ELit (litCons { litName = tc_Ratio, litArgs = [tInteger], litType = eStar })
    tChar = ELit (litCons { litName = tChar, litArgs = [], litType = eStar })
    tBool = ELit (litCons { litName = tBool, litArgs = [], litType = eStar })
    tUnit = ELit (litCons { litName = tUnit, litArgs = [], litType = eStar })
    tString =  (ELit (litCons { litName = tc_List, litArgs = [tChar], litType = eStar }))
    tInteger = ELit (litCons { litName = tInteger, litArgs = [], litType = eStar })
    tWorld__ = ELit (litCons { litName = tWorld__, litArgs = [], litType = eHash })
    tIntzh = ELit (litCons { litName = tIntzh, litArgs = [], litType = eHash })
    tEnumzh = ELit (litCons { litName = tEnumzh, litArgs = [], litType = eHash })
    tIntegerzh = ELit (litCons { litName = tIntegerzh, litArgs = [], litType = eHash })
    tCharzh = ELit (litCons { litName = tCharzh, litArgs = [], litType = eHash })

instance ConNames E where
    vTrue = ELit vTrue
    vFalse = ELit vFalse
    vUnit  = ELit vUnit

instance ConNames (Lit E E) where
    vTrue  = (litCons { litName = dc_Boolzh, litArgs = [ELit (LitInt 1 tEnumzh)], litType = tBool })
    vFalse = (litCons { litName = dc_Boolzh, litArgs = [ELit (LitInt 0 tEnumzh)], litType = tBool })
    vUnit  = (litCons { litName = vUnit, litArgs = [], litType = tUnit })



tFunc a b = ePi (tVr 0 a) b

-- values



tvrSilly = tVr ((-1)) Unknown

-----------------
-- E constructors
-----------------



ePi a b = EPi a b

eLam v (EError s t) = EError s (ePi v t)
eLam v t = ELam v t


-- | throw away first n EPi terms
discardArgs :: Int -> E -> E
discardArgs 0 e = e
discardArgs n (EPi _ b) | n > 0 = discardArgs (n - 1) b
discardArgs _ _ = error "discardArgs"


tvrName :: Monad m => TVr  -> m Name
tvrName (TVr {tvrIdent =  n }) | Just a <- fromId n = return a
tvrName tvr = fail $ "TVr is not Name: " ++ show tvr

tvrShowName :: TVr -> String
tvrShowName t = maybe ('x':(show $ tvrIdent t)) show (tvrName t)


modAbsurd = "Jhc@.Absurd"
modBox    = "Jhc@.Box"


nameConjured :: String -> E -> Name
nameConjured mod n = toName TypeConstructor (mod,f n "") where
    f (ESort s) = shows s
    f (EPi TVr { tvrType = t1 } t2) = ('^':) . shows t1 . shows t2
    f _ = error $ "nameConjured: " ++ show (mod,n)

fromConjured :: Monad m => String -> Name -> m E
fromConjured mod n = maybeM ("fromConjured: " ++ show (mod,n)) $ do
    let f s = funit s `mplus` flam s
        flam ('^':xs) = do (x,rs) <- f xs; (y,gs) <- f rs; return (EPi tvr { tvrType = x } y,gs)
        flam _ = Nothing
        funit ('*':xs) = return (eStar,xs)
        funit ('#':xs) = return (eHash,xs)
        funit ('!':xs) = return (ESort EBang,xs)
        funit ('(':'#':')':xs) = return (ESort ETuple,xs)
        funit _ = Nothing
    (TypeConstructor,(mod',an)) <- return $  fromName n
    guard (mod' == mod)
    (r,"") <- f an
    return r



isBottom EError {} = True
isBottom _ = False


caseBodiesMapM :: Monad m => (E -> m E) -> E -> m E
caseBodiesMapM f ec@ECase { eCaseAlts = as, eCaseDefault = d } = do
    let g (Alt l e) = f e >>= return . Alt l
    as' <- mapM g as
    d' <- T.mapM f d
    return $ caseUpdate ec { eCaseAlts = as', eCaseDefault = d' }
caseBodiesMapM _ _ = error "caseBodiesMapM"

eToList :: Monad m => E -> m  [E]
eToList (ELit LitCons { litName = n, litArgs = [e,b] }) | vCons == n = eToList b >>= \x -> return (e:x)
eToList (ELit LitCons { litName = n, litArgs = [] }) | vEmptyList == n = return []
eToList _ = fail "eToList: not list"

toString (ELit LitCons { litName = n, litArgs = [], litType = t }) = if vEmptyList == n && t == tString then return "" else fail "not a string"
toString x = eToList x >>= mapM fromChar where
    fromChar (ELit LitCons { litName = dc, litArgs = [ELit (LitInt ch t)] }) | dc == dc_Char && t == tCharzh = return (chr $ fromIntegral ch)
    fromChar _ = fail "fromChar: not char"



ltTuple ts = ELit $ litCons { litName = nameTuple TypeConstructor (length ts), litArgs = ts, litType = eStar }
ltTuple' ts = ELit $ litCons { litName = unboxedNameTuple TypeConstructor (length ts), litArgs = ts, litType = eHash }

p_unsafeCoerce = primPrim "unsafeCoerce"
p_dependingOn = primPrim "dependingOn"
p_toTag = primPrim "toTag"
p_fromTag = primPrim "fromTag"

fromUnboxedTuple :: Monad m => E -> m [E]
fromUnboxedTuple (ELit LitCons { litName = n, litArgs = as }) | Just _ <- fromUnboxedNameTuple n = return as
fromUnboxedTuple _ = fail "fromUnboxedTuple: not a tuple"

isUnboxedTuple m = isJust (fromUnboxedTuple m)

