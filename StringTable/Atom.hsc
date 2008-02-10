{-# OPTIONS_GHC -fffi -XTypeSynonymInstances -XDeriveDataTypeable  #-}
module StringTable.Atom(
    Atom(),
    ToAtom(..),
    FromAtom(..),
    intToAtom,
    unsafeIntToAtom,
    atomCompare,
    dumpTable,
    dumpStringTableStats
    ) where

#include "StringTable_cbits.h"

import qualified Data.ByteString as BS
import qualified Data.ByteString.Internal as BS
import System.IO.Unsafe
import Foreign
import Data.Word
import Data.Char
import Foreign.C
import Data.Monoid
import Data.Dynamic
import Data.Bits



newtype Atom = Atom (#type atom_t)
    deriving(Typeable,Eq,Ord)

class FromAtom a where
    fromAtom :: Atom -> a
    fromAtomIO :: Atom -> IO a

    fromAtomIO a = return (fromAtom a)
    fromAtom a = unsafePerformIO (fromAtomIO a)

class ToAtom a where
    toAtom :: a -> Atom
    toAtomIO :: a -> IO Atom

    toAtomIO a = return (toAtom a)
    toAtom a = unsafePerformIO (toAtomIO a)

instance ToAtom Atom where
    toAtom x = x

instance FromAtom Atom where
    fromAtom x = x

instance ToAtom Char where
    toAtom x = toAtom [x]

instance ToAtom CStringLen where
    toAtomIO (cs,len) = do
        if (len > (#const MAX_ENTRY_SIZE))
            then fail "StringTable: atom is too big"
            else stAdd cs (fromIntegral len)



instance ToAtom CString where
    toAtomIO cs = do
        len <- BS.c_strlen cs
        toAtomIO (cs,fromIntegral len :: Int)

instance ToAtom String where
    toAtomIO s = toAtomIO (BS.pack (toUTF s))

instance FromAtom String where
    fromAtom = fromUTF . BS.unpack . fromAtom

instance ToAtom BS.ByteString where
    toAtomIO bs = BS.useAsCStringLen bs toAtomIO

instance FromAtom CStringLen where
    fromAtom a@(Atom v) = (stPtr a,fromIntegral $ v .&. (#const ATOM_LEN_MASK))

instance FromAtom Word where
    fromAtom (Atom i) = fromIntegral i

instance FromAtom Int where
    fromAtom (Atom i) = fromIntegral i

instance FromAtom BS.ByteString where
    fromAtomIO a = do
        (p,l) <- fromAtomIO a :: IO CStringLen
        BS.packCStringLen (p,fromIntegral l)
    --    fp <- newForeignPtr_ =<< (castPtr `fmap` peek p)
    --    return $ BS.fromForeignPtr fp 0 (fromIntegral l)

instance Monoid Atom where
    mempty = toAtom BS.empty
    mappend x y = unsafePerformIO $ atomAppend x y

instance Show Atom where
    showsPrec _ atom = (fromAtom atom ++)

instance Read Atom where
    readsPrec _ s = [ (toAtom s,"") ]

intToAtom :: Monad m => Int -> m Atom
intToAtom i = if 0 /= (#const VALID_BITMASK) .&. i then return (Atom $ fromIntegral i) else fail $ "intToAtom: " ++ show i

unsafeIntToAtom :: Int -> Atom
unsafeIntToAtom x = Atom (fromIntegral x)

foreign import ccall unsafe "stringtable_lookup" stAdd :: CString -> CInt -> IO Atom
foreign import ccall unsafe "stringtable_ptr" stPtr :: Atom -> CString
foreign import ccall unsafe "stringtable_get" stGet :: Atom -> Ptr CChar -> IO CInt
foreign import ccall unsafe "stringtable_stats" dumpStringTableStats :: IO ()
foreign import ccall unsafe "dump_table" dumpTable :: IO ()
foreign import ccall unsafe "atom_append" atomAppend :: Atom -> Atom -> IO Atom
foreign import ccall unsafe "lexigraphic_compare" c_atomCompare :: Atom -> Atom -> CInt

atomCompare a b = if c == 0 then EQ else if c > 0 then GT else LT where
    c = c_atomCompare a b



-- | Convert Unicode characters to UTF-8.
toUTF :: String -> [Word8]
toUTF [] = []
toUTF (x:xs) | ord x<=0x007F = (fromIntegral $ ord x):toUTF xs
	     | ord x<=0x07FF = fromIntegral (0xC0 .|. ((ord x `shift` (-6)) .&. 0x1F)):
			       fromIntegral (0x80 .|. (ord x .&. 0x3F)):
			       toUTF xs
	     | otherwise     = fromIntegral (0xE0 .|. ((ord x `shift` (-12)) .&. 0x0F)):
			       fromIntegral (0x80 .|. ((ord x `shift` (-6)) .&. 0x3F)):
			       fromIntegral (0x80 .|. (ord x .&. 0x3F)):
			       toUTF xs

-- | Convert UTF-8 to Unicode.

fromUTF :: [Word8] -> String
fromUTF xs = fromUTF' (map fromIntegral xs) where
    fromUTF' [] = []
    fromUTF' (all@(x:xs))
	| x<=0x7F = (chr (x)):fromUTF' xs
	| x<=0xBF = err
	| x<=0xDF = twoBytes all
	| x<=0xEF = threeBytes all
	| otherwise   = err
    twoBytes (x1:x2:xs) = chr  ((((x1 .&. 0x1F) `shift` 6) .|.
			       (x2 .&. 0x3F))):fromUTF' xs
    twoBytes _ = error "fromUTF: illegal two byte sequence"

    threeBytes (x1:x2:x3:xs) = chr ((((x1 .&. 0x0F) `shift` 12) .|.
				    ((x2 .&. 0x3F) `shift` 6) .|.
				    (x3 .&. 0x3F))):fromUTF' xs
    threeBytes _ = error "fromUTF: illegal three byte sequence"

    err = error "fromUTF: illegal UTF-8 character"