module Name.Id(
    Id(),
    IdMap(),
    IdNameT(),
    IdSet(),
    addBoundNamesIdMap,
    addBoundNamesIdSet,
    addNamesIdSet,
    idMapToIdSet,
    idNameBoundNames,
    idNameUsedNames,
    idSetToIdMap,
    idSetToList,
    runIdNameT',
    runIdNameT
    )where

import Control.Monad
import Control.Monad.State
import Data.FunctorM
import Data.Monoid
import Data.Typeable
import qualified Data.IntMap  as IM
import qualified Data.IntSet as IS

import Util.HasSize
import Util.Inst()
import Util.NameMonad
import Util.SetLike as S

-- TODO - make this a newtype
type Id = Int


-- IdSet


newtype IdSet = IdSet IS.IntSet
    deriving(Typeable,Monoid,HasSize,SetLike,BuildSet Id,ModifySet Id,IsEmpty,Eq,Ord)


idSetToList :: IdSet -> [Id]
idSetToList (IdSet is) = IS.toList is

idToInt :: Id -> Int
idToInt = id


-- IdMap

newtype IdMap a = IdMap (IM.IntMap a)
    deriving(Typeable,Monoid,HasSize,SetLike,BuildSet (Id,a),MapLike Id a,Functor,FunctorM,Show,IsEmpty,Eq,Ord)


idSetToIdMap :: (Id -> a) -> IdSet -> IdMap a
idSetToIdMap f (IdSet is) = IdMap $ IM.fromDistinctAscList [ (x,f x) |  x <- IS.toAscList is]

idMapToIdSet :: IdMap a -> IdSet
idMapToIdSet (IdMap im) = IdSet $ IS.fromDistinctAscList (IM.keys im)


-- | Name monad transformer.
newtype IdNameT m a = IdNameT (StateT (IdSet, IdSet) m a)
    deriving(Monad, MonadTrans, Functor, MonadFix, MonadPlus, MonadIO)

-- | Get bound and used names
idNameBoundNames :: Monad m => IdNameT m IdSet
idNameBoundNames = IdNameT $ do
    (_used,bound) <- get
    return bound
idNameUsedNames :: Monad m => IdNameT m IdSet
idNameUsedNames = IdNameT $  do
    (used,_bound) <- get
    return used

-- | Run the name monad transformer.
runIdNameT :: (Monad m) => IdNameT m a -> m a
runIdNameT (IdNameT x) = liftM fst $ runStateT x (mempty,mempty)

runIdNameT' :: (Monad m) => IdNameT m a -> m (a,IdSet)
runIdNameT' (IdNameT x) = do
    (r,(used,bound)) <- runStateT x (mempty,mempty)
    return (r,bound)

fromIdNameT (IdNameT x) = x

instance Monad m => NameMonad Id (IdNameT m) where
    addNames ns = IdNameT $ do
        modify (\ (used,bound) -> (fromList ns `union` used, bound) )
    addBoundNames ns = IdNameT $ do
        let nset = fromList ns
        modify (\ (used,bound) -> (nset `union` used, nset `union` bound) )
    uniqueName n = IdNameT $ do
        (used,bound) <- get
        if n `member` bound then fromIdNameT newName else put (insert n used,insert n bound) >> return n
    newNameFrom vs = IdNameT $ do
        (used,bound) <- get
        let f (x:xs)
                | x `member` used = f xs
                | otherwise = x
            f [] = error "newNameFrom: finite list!"
            nn = f vs
        put (insert nn used, insert nn bound)
        return nn
    newName  = IdNameT $ do
        (used,bound) <- get
        let genNames i = [st, st + 2 ..]  where
                st = abs i + 2 + abs i `mod` 2
        fromIdNameT $ newNameFrom  (genNames (size used + size bound))

addNamesIdSet nset = IdNameT $ do
    modify (\ (used,bound) -> (nset `union` used, bound) )
addBoundNamesIdSet nset = IdNameT $ do
    modify (\ (used,bound) -> (nset `union` used, nset `union` bound) )

addBoundNamesIdMap nmap = IdNameT $ do
    modify (\ (used,bound) -> (nset `union` used, nset `union` bound) ) where
        nset = idMapToIdSet nmap


