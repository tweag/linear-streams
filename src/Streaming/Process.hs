{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE RecordWildCards #-}

-- | This module provides functions that take one input
-- stream and produce one output stream. These are functions that
-- process a single stream.
module Streaming.Process
  (
  -- * Stream processors
  -- ** Splitting and inspecting streams of elements
    next
  , uncons
  , splitAt
  , split
  --, breaks
  --, break
  --, breakWhen
  --, span
  --, group
  --, groupBy
  -- ** Sum and compose manipulation
  --, distinguish
  --, switch
  --, seperate
  --, unseparate
  --, eitherToSum
  --, sumToEither
  --, sumToCompose
  --, composeToSum
  -- * Partitions
  --, partitionEithers
  --, partition
  -- * Maybes
  --, catMaybes
  , mapMaybe
  -- ** Direct Transformations
  , map
  --, mapM
  --, maps
  --, mapped
  --, for
  --, with
  --, subst
  --, copy
  --, copy'
  --, store
  --, chain
  --, sequence
  --, filter
  --, filterM
  --, delay
  --, intersperse
  --, take
  --, takeWhile
  --, takeWhileM
  --, drop
  --, dropWhile
  --, concat
  --, scan
  --, scanM
  --, scanned
  --, read
  --, show
  --, cons
  --, duplicate
  --, duplicate'
  ) where

import Streaming.Type
import Prelude.Linear ((&), ($), (.))
import Prelude (Maybe(..), Either(..), Bool(..), Int, fromInteger,
               Ordering(..), Num(..), Eq(..), id)
import qualified Prelude
import Data.Unrestricted.Linear
import qualified Control.Monad.Linear as Control
import Control.Monad.Linear.Builder (BuilderType(..), monadBuilder)
import GHC.Stack


-- # Internal Library
-------------------------------------------------------------------------------

-- | When chunking streams, it's useful to have a combinator
-- that can add an element to the functor that is itself a stream.
-- Basically `consFirstChunk 42 [[1,2,3],[4,5]] = [[42,1,2,3],[4,5]]`.
consFirstChunk :: Control.Monad m =>
  a -> Stream (Stream (Of a) m) m r #-> Stream (Stream (Of a) m) m r
consFirstChunk a stream = stream & \case
    Return r -> Step (Step (a :> Return (Return r)))
    Effect m -> Effect $ Control.fmap (consFirstChunk a) m
    Step f -> Step (Step (a :> f))
  where
    Builder{..} = monadBuilder


-- # Splitting and inspecting streams of elements
-------------------------------------------------------------------------------

next :: Control.Monad m =>
  Stream (Of a) m r #-> m (Either r (a, Stream (Of a) m r))
next stream = stream & \case
  Return r -> return $ Left r
  Effect ms -> ms >>= next
  Step (a :> as) -> return $ Right (a, as)
  where
    Builder{..} = monadBuilder

uncons :: (Consumable r, Control.Monad m) =>
  Stream (Of a) m r #-> m (Maybe (a, Stream (Of a) m r))
uncons  stream = stream & \case
  Return r -> lseq r $ return Nothing
  Effect ms -> ms >>= uncons
  Step (a :> as) -> return $ Just (a, as)
  where
    Builder{..} = monadBuilder

splitAt :: (HasCallStack, Control.Monad m, Control.Functor f) =>
  Int -> Stream f m r #-> Stream f m (Stream f m r)
splitAt n stream = Prelude.compare n 0 & \case
  LT -> Prelude.error "splitAt called with negative integer" $ stream
  EQ -> Return stream
  GT -> stream & \case
    Return r -> Prelude.error "splitAt called with too large index" $ r
    Effect m -> Effect $ m >>= (return . splitAt n)
    Step f -> Step $ Control.fmap (splitAt (n-1)) f
  where
    Builder{..} = monadBuilder

split :: (Eq a, Control.Monad m) =>
  a -> Stream (Of a) m r #-> Stream (Stream (Of a) m) m r
split x stream = stream & \case
  Return r -> Return r
  Effect m -> Effect $ m >>= (return . split x)
  Step (a :> as) -> case a == x of
    True -> split x as
    False -> consFirstChunk a (split x as)
  where
    Builder{..} = monadBuilder

break :: Control.Monad m =>
  (a -> Bool) -> Stream (Of a) m r #-> Stream (Of a) m (Stream (Of a) m r)
break f stream = stream & \case
  Return r -> Return (Return r)
  Effect m -> Effect $ Control.fmap (break f) m
  Step (a :> as) -> case f a of
    True -> Return $ Step (a :> as)
    False -> Step (a :> (break f as))
  where
    Builder{..} = monadBuilder

-- | Elements that fail the predicate are grouped, and elements that
-- pass the predicate are discarded
breaks :: Control.Monad m =>
  (a -> Bool) -> Stream (Of a) m r #-> Stream (Stream (Of a) m) m r
breaks f stream = stream & \case
  Return r -> Return r
  Effect m -> Effect $ Control.fmap (breaks f) m
  Step (a :> as) -> case f a of
    True -> breaks f as
    False -> consFirstChunk a (breaks f as)
  where
    Builder{..} = monadBuilder

-- The funny type of this seems to be made to interoperate well with 
-- `purely` from the `foldl` package.
breakWhen :: Control.Monad m => (x -> a -> x) -> x -> (x -> b) -> (b -> Bool)
          -> Stream (Of a) m r #-> Stream (Of a) m (Stream (Of a) m r)
breakWhen step x end pred stream = stream & \case
  Return r -> Return (Return r)
  Effect m -> Effect $ Control.fmap (breakWhen step x end pred) m
  Step (a :> as) -> case pred (end (step x a)) of
    False -> Step $ a :> (breakWhen step (step x a) end pred as)
    True -> Return (Step (a :> as))

breakWhen' :: Control.Monad m =>
  (a -> Bool) -> Stream (Of a) m r #-> Stream (Of a) m (Stream (Of a) m r)
breakWhen' f stream = breakWhen (\x a -> f a) True id id stream

span :: Control.Monad m =>
  (a -> Bool) -> Stream (Of a) m r #-> Stream (Of a) m (Stream (Of a) m r)
span f = break (Prelude.not Prelude.. f)

groupBy :: Control.Monad m =>
  (a -> a -> Bool) -> Stream (Of a) m r #-> Stream (Stream (Of a) m) m r
groupBy equals stream = stream & \case
  Return r -> Return r
  Effect m -> Effect $ Control.fmap (groupBy equals) m
  Step (a :> as) -> as & \case
    Return r -> Step (Step (a :> Return (Return r)))
    Effect m -> Effect $ m >>= (\s -> return $ groupBy equals (Step (a :> s)))
    Step (a' :> as') -> case equals a a' of
      False -> Step $ Step $ a :> (Return $ groupBy equals (Step (a' :> as')))
      True -> Step $ Step $ a :> (Step $ a' :> (Return $ groupBy equals as'))
  where
    Builder{..} = monadBuilder

group :: (Control.Monad m, Eq a) =>
  Stream (Of a) m r #-> Stream (Stream (Of a) m) m r
group = groupBy (==)


-- # Sum and compose manipulation
-------------------------------------------------------------------------------

  --, distinguish
  --, switch
  --, seperate
  --, unseparate
  --, eitherToSum
  --, sumToEither
  --, sumToCompose
  --, composeToSum

-- # Partitions
-------------------------------------------------------------------------------

partition :: Control.Monad m =>
  (a -> Bool) -> Stream (Of a) m r #-> Stream (Of a) (Stream (Of a) m) r
partition pred = loop
  where
    Builder{..} = monadBuilder
    loop :: Stream (Of a) m r #-> Stream (Of a) (Stream (Of a) m) r
    loop stream = stream & \case
      Return r -> Return r
      Effect m -> Effect (Control.fmap loop (Control.lift m))
      Step (a :> as) -> case pred a of
        True -> Step (a :> loop as)
        False -> Effect $ yield a >> return (loop rest)

-- partitionEithers


-- # Maybes
-------------------------------------------------------------------------------

catMaybes :: Control.Monad m => Stream (Of (Maybe a)) m r #-> Stream (Of a) m r
catMaybes stream = stream & \case
  Return r -> Return r
  Effect m -> Effect $ Control.fmap catMaybes m
  Step (maybe :> as) -> case maybe of
    Nothing -> catMaybes as
    Just a -> Step $ a :> (catMaybes as)
  where
    Builder{..} = monadBuilder

mapMaybe :: Control.Monad m =>
  (a -> Maybe b) -> Stream (Of a) m r #-> Stream (Of b) m r
mapMaybe f stream = stream & \case
  Return r -> Return r
  Effect ms -> Effect $ ms >>= (return . mapMaybe f)
  Step (a :> s) -> case f a of
    Just b -> Step $ b :> (mapMaybe f s)
    Nothing -> mapMaybe f s
  where
    Builder{..} = monadBuilder


-- # Direct Transformations
-------------------------------------------------------------------------------

map :: Control.Monad m => (a -> b) -> Stream (Of a) m r #-> Stream (Of b) m r
map f stream = stream & \case
  Return r -> Return r
  Step (a :> rest) -> Step $ (f a) :> map f rest
  Effect ms -> Effect $ Control.fmap (map f) ms

  --, mapM
  --, maps
  --, mapped
  --, for
  --, with
  --, subst
  --, copy
  --, copy'
  --, store
  --, chain
  --, sequence
  --, filter
  --, filterM
  --, delay
  --, intersperse
  --, take
  --, takeWhile
  --, takeWhileM
  --, drop
  --, dropWhile
  --, concat
  --, scan
  --, scanM
  --, scanned
  --, read
  --, show
  --, cons
  --, duplicate
  --, duplicate'

