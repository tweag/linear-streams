{-# OPTIONS_HADDOCK hide #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | This module provides all functions which produce a
-- 'Stream (Of a) m r' from some given non-stream inputs.
module Streaming.Internal.Produce
  ( -- * Constructing 'Stream's
    yield
  , each'
  , unfoldr
  , stdinLnN
  , stdinLnUntil
  , stdinLnUntilM
  , stdinLnZip
  , readLnN
  , readLnUntil
  , readLnUntilM
  , readLnZip
  , fromHandle
  , readFile
  , iterate
  , iterateM
  , replicate
  , replicateM
  , untilRight
  --, cycleN
  --, cycleZip
  --, enumFromN
  --, enumFromZip
  --, enumFromThen
  --, enumFromThenZip
  ) where

import Streaming.Internal.Type
import Streaming.Internal.Many
import Streaming.Internal.Process
import Streaming.Internal.Consume
import Prelude.Linear (($), (&))
import Prelude (Either(..), Read, Bool(..), FilePath, (.), Enum(..),
               Num(..), Int, otherwise, Eq(..), Ord(..), String)
import qualified Prelude
import qualified Control.Monad.Linear as Control
import Data.Unrestricted.Linear
import System.IO.Linear
import System.IO.Resource
import qualified System.IO as System
import Text.Read (readMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import GHC.Stack


-- # The Stream Constructors
-------------------------------------------------------------------------------

{- Remark.

The constructors that replace the constructors for infinite streams are in this
module. See the readme for an explanation of the workarounds for infinite
streams.

Basically for the vast majority of cases it suffices to have variants
of infinite stream constructors that either (1) construct a finite number
of elements, (2) construct until a boolean condition is met, or (3)
construct enough elements to be able to zip with some finite stream.

These functions have the postfixes "N", "Until", "UntilM", or "Zip".

Ommisions:

 - @replicateZip@ is easily replaced by mapping the finite stream
 with @\x -> (x,a)@ for the @a@ we want to replicate

-}

{-| A singleton stream

>>> stdoutLn $ yield "hello"
hello

>>> S.sum $ do {yield 1; yield 2; yield 3}
6 :> ()

-}
yield :: Control.Monad m => a -> Stream (Of a) m ()
yield x = Step $ x :> Return ()
{-# INLINE yield #-}

{- | Stream the elements of a pure, foldable container.

>>> S.print $ each' [1..3]
1
2
3

-}
each' :: Control.Monad m => [a] -> Stream (Of a) m ()
each' xs = Prelude.foldr (\a stream -> Step $ a :> stream) (Return ()) xs
{-# INLINABLE each' #-}

{-| Build a @Stream@ by unfolding steps starting from a seed. In particular note
    that @S.unfoldr S.next = id@.

-}
unfoldr :: Control.Monad m =>
  (s #-> m (Either r (Unrestricted a, s))) -> s #-> Stream (Of a) m r
unfoldr step s = unfoldr' step s
  where
    unfoldr' :: Control.Monad m =>
      (s #-> m (Either r (Unrestricted a, s))) -> s #-> Stream (Of a) m r
    unfoldr' step s = Effect $ step s Control.>>= \case
      Left r -> Control.return $ Return r
      Right (Unrestricted a,s') ->
        Control.return $ Step $ a :> unfoldr step s'
{-# INLINABLE unfoldr #-}

-- | @stdinLnN n@ is a stream of @n@ lines from standard input
stdinLnN :: Int -> Stream (Of Text) IO ()
stdinLnN n = loop n
  where
    loop :: Int -> Stream (Of Text) IO ()
    loop n | n <= 0 = Return ()
    loop n = Control.do
      Unrestricted line <- Control.lift $ fromSystemIOU System.getLine
      yield (Text.pack line)
      loop (n-1)
{-# INLINABLE stdinLnN #-}

-- | Provides a stream of standard input and omits the first line
-- that satisfies the predicate, possibly requiring IO
stdinLnUntilM :: (Text -> IO Bool) -> Stream (Of Text) IO ()
stdinLnUntilM f = loop f
  where
    loop :: (Text -> IO Bool) -> Stream (Of Text) IO ()
    loop f = Control.do
      Unrestricted line <- Control.lift $ fromSystemIOU System.getLine
      let textLine = Text.pack line
      test <- Control.lift $ f textLine
      test & \case
        True -> Control.return ()
        False -> Control.do
          yield textLine
          loop f
{-# INLINABLE stdinLnUntilM #-}

-- | Provides a stream of standard input and omits the first line
-- that satisfies the predicate
stdinLnUntil :: (Text -> Bool) -> Stream (Of Text) IO ()
stdinLnUntil f = stdinLnUntilM (\t -> Control.return (f t))
{-# INLINE stdinLnUntil #-}

-- | Given a finite stream, provide a stream of lines of standard input
-- zipped with that finite stream
stdinLnZip :: Stream (Of x) IO r #-> Stream (Of (Text, x)) IO r
stdinLnZip = loop
  where
    loop :: Stream (Of x) IO r #-> Stream (Of (Text, x)) IO r
    loop stream = stream & \case
      Return r -> Return r
      Effect m -> Effect $ Control.fmap loop m
      Step (x :> rest) -> Control.do
        Unrestricted line <- Control.lift $ fromSystemIOU System.getLine
        yield (Text.pack line, x)
        loop rest
{-# INLINABLE stdinLnZip #-}

-- Remark. To avoid unpacking a re-reading things in the logic below,
-- we need to repeat some of the computation above. This could be made
-- cleaner with internal stdinLn* functions on Strings that we wrap as needed.

readLnN :: Read a => Int -> Stream (Of a) IO ()
readLnN n = loop n
  where
    loop :: Read a => Int -> Stream (Of a) IO ()
    loop n | n <= 0 = Return ()
    loop n = Control.do
      Unrestricted line <- Control.lift $ fromSystemIOU System.getLine
      let value = Prelude.read line
      yield value
      loop (n-1)
{-# INLINABLE readLnN #-}

readLnUntilM :: Read a => (a -> IO Bool) -> Stream (Of a) IO ()
readLnUntilM f = loop f
  where
    loop :: Read a => (a -> IO Bool) -> Stream (Of a) IO ()
    loop f = Control.do
      Unrestricted line <- Control.lift $ fromSystemIOU System.getLine
      let value = Prelude.read line
      test <- Control.lift $ f value
      test & \case
        True -> Return ()
        False -> Control.do
          yield value
          loop f
{-# INLINABLE readLnUntilM #-}

readLnUntil :: Read a => (a -> Bool) -> Stream (Of a) IO ()
readLnUntil f = readLnUntilM (\a -> Control.return (f a))
{-# INLINE readLnUntil #-}

readLnZip :: Read a => Stream (Of x) IO r #-> Stream (Of (a, x)) IO r
readLnZip = loop
  where
    loop :: Read a => Stream (Of x) IO r #-> Stream (Of (a, x)) IO r
    loop stream = stream & \case
      Return r -> Return r
      Effect m -> Effect $ Control.fmap loop m
      Step (x :> rest) -> Control.do
        Unrestricted line <- Control.lift $ fromSystemIOU System.getLine
        yield (Prelude.read line, x)
        loop rest
{-# INLINE readLnZip #-}

-- Note: we use the RIO monad from linear base to enforce
-- the protocol of file handles and file I/O
fromHandle :: Handle #-> Stream (Of Text) RIO ()
fromHandle h = loop h
  where
    loop :: Handle #-> Stream (Of Text) RIO ()
    loop h = Control.do
      (Unrestricted isEOF, h') <- Control.lift $ hIsEOF h
      case isEOF of
        True -> Control.do
          Control.lift $ hClose h'
          Control.return ()
        False -> Control.do
          (Unrestricted text, h'') <- Control.lift $ hGetLine h'
          yield text
          fromHandle h''
{-# INLINABLE fromHandle #-}

{-| Read the lines of a file given the filename.

-}
readFile :: FilePath -> Stream (Of Text) RIO ()
readFile path = Control.do
  handle <- Control.lift $ openFile path System.ReadMode
  fromHandle handle

-- | Iterate a pure function from a seed value, streaming the results forever
iterate :: Control.Monad m => (a -> a) -> a -> Stream (Of a) m r
iterate = loop
  where
    loop :: Control.Monad m => (a -> a) -> a -> Stream (Of a) m r
    loop step x = Effect $ Control.return $ Step $ x :> iterate step (step x)
{-# INLINABLE iterate #-}

-- | Iterate a monadic function from a seed value, streaming the results forever
iterateM :: Control.Monad m =>
  (a -> m (Unrestricted a)) -> m (Unrestricted a) #-> Stream (Of a) m r
iterateM stepM mx = Effect $ Control.do
  Unrestricted x <- mx
  Control.return $ Step $ x :> iterateM stepM (stepM x)
{-# INLINABLE iterateM #-}

-- | Repeat an element several times.
replicate :: (HasCallStack, Control.Monad m) => Int -> a -> Stream (Of a) m ()
replicate n a
  | n < 0 = Prelude.error "Cannot replicate a stream of negative length"
  | otherwise = loop n a
    where
      loop :: Control.Monad m => Int -> a -> Stream (Of a) m ()
      loop n a
        | n == 0 = Return ()
        | otherwise = Effect $ Control.return $ Step $ a :> loop (n-1) a
{-# INLINABLE replicate #-}

{-| Repeat an action several times, streaming its results.

>>> import qualified Unsafe.Linear as Unsafe
>>> import qualified Data.Time as Time
>>> let getCurrentTime = fromSystemIO (Unsafe.coerce Time.getCurrentTime)
>>> S.print $ S.replicateM 2 getCurrentTime
2015-08-18 00:57:36.124508 UTC
2015-08-18 00:57:36.124785 UTC

-}
replicateM :: Control.Monad m =>
  Int -> m (Unrestricted a) -> Stream (Of a) m ()
replicateM n ma
  | n < 0 = Prelude.error "Cannot replicate a stream of negative length"
  | otherwise = loop n ma
    where
      loop :: Control.Monad m => Int -> m (Unrestricted a) -> Stream (Of a) m ()
      loop n ma
        | n == 0 = Return ()
        | otherwise = Effect $ Control.do
          Unrestricted a <- ma
          Control.return $ Step $ a :> (replicateM (n-1) ma)

untilRight :: forall m a r . Control.Monad m =>
  m (Either (Unrestricted a) r) -> Stream (Of a) m r
untilRight mEither = Effect loop
  where
    loop :: m (Stream (Of a) m r)
    loop = Control.do
      either <- mEither
      either & \case
        Left (Unrestricted a) ->
          Control.return $ Step $ a :> (untilRight mEither)
        Right r -> Control.return $ Return r
{-# INLINABLE untilRight #-}

-- | Cycle a stream a finite number of times
cycleN :: forall r f m. (Control.Monad m, Control.Functor f, Consumable r) =>
  Int -> Stream f m r -> Stream f m r
cycleN = loop
  where
    loop :: Int -> Stream f m r -> Stream f m r
    loop n stream | n <= 1 = stream
    loop n stream = Control.do
      r <- stream
      lseq r (loop (n-1) stream)
{-# INLINABLE cycleN #-}

-- | @cycleZip s1 s2@ will cycle @s2@ just enough to zip with the given finite
-- stream @s1@. Note that we consume all the effects of the remainder of the
-- cycled stream @s2@. That is, we consume @s2@ the smallest natural number of
-- times we need to zip.
cycleZip :: forall a b m r s. (Control.Monad m, Consumable s) =>
  Stream (Of a) m r #-> Stream (Of b) m s -> Stream (Of (a,b)) m r
cycleZip s1 s2 = loop s1 s2
  where
  loop :: Stream (Of a) m r #-> Stream (Of b) m s #-> Stream (Of (a,b)) m r
  loop s1' s2' = Control.do
    residual <- zip' s1' (Control.fmap consume s2')
    residual & \case
      (Left r, Left ()) -> Control.return r
      (Left r, Right rest) -> Control.do
        Control.lift $ effects rest
        Control.return r
      (Right as, Left ()) -> loop as s2
      (Right as, Right bs) -> loop as (bs Control.>> s2)
{-# INLINABLE cycleZip #-}

{-| An finite sequence of enumerable values at a fixed distance, determined
   by the first and second values.

>>> S.print $ S.enumFromThenN 3 100 200
100
200
300

-}
enumFromThenN :: (Control.Monad m, Enum e) => Int -> e -> e -> Stream (Of e) m ()
enumFromThenN = loop
  where
    loop :: (Control.Monad m, Enum e) => Int -> e -> e -> Stream (Of e) m ()
    loop n e e'
      | n <= 0 = Return ()
      | Prelude.otherwise = yield e Control.>> enumFromThenN (n-1) e' e''
      where
        -- e'' = e' + (e' - e)
        e'' = toEnum ((2 * fromEnum e') - (fromEnum e))
{-# INLINABLE enumFromThenN #-}

-- | A finite sequence of enumerable values at a fixed distance determined
-- by the first and second values. The length is limited by zipping
-- with a given finite stream, i.e., the first argument.
enumFromThenZip :: (Control.Monad m, Enum e) =>
  Stream (Of a) m r #-> e -> e -> Stream (Of (a,e)) m r
enumFromThenZip stream e e' = stream & \case
  Return r -> Return r
  Effect m -> Effect $ Control.fmap (\s -> enumFromThenZip s e e') m
  Step (a :> rest) -> Step $ (a,e) :> (enumFromThenZip rest e' e'')
    where
        -- e'' = e' + (e' - e)
        e'' = toEnum ((2 * fromEnum e') - (fromEnum e))
{-# INLINABLE enumFromThenZip #-}

-- | Like 'enumFromThenN' but where the next element in the enumeration is just
-- the successor @succ n@ for a given enum @n@.
enumFromN :: (Control.Monad m, Enum e) => Int -> e -> Stream (Of e) m ()
enumFromN n e = enumFromThenN n e (succ e)
{-# INLINE enumFromN #-}

-- | Like 'enumFromThenZip' but where the next element in the enumeration is just
-- the successor @succ n@ for a given enum @n@.
enumFromZip :: (Control.Monad m, Enum e) =>
  Stream (Of a) m r #-> e -> Stream (Of (a,e)) m r
enumFromZip stream e = enumFromThenZip stream e (succ e)
{-# INLINE enumFromZip #-}

