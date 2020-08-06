{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE RecordWildCards #-}

-- | This module contains all functions that do something with
-- multiple streams as input or output. This includes combining
-- streams, splitting a stream, etc.
module Streaming.Many
  (
  -- * Zips and unzips
    zip
  , zipWith
  , zip3
  , zipWith3
  , unzip
  , partitionEithers
  , partition
  -- * Merging
  , merge
  , mergeOn
  , mergeBy
  ) where

import Streaming.Type
import Streaming.Consume
import Prelude (undefined, Bool(..), Either(..), Ord(..), Ordering(..), (.))
import Prelude.Linear (($), (&))
import qualified Prelude.Linear as Linear
import qualified Control.Monad.Linear as Control
import Control.Monad.Linear.Builder (BuilderType(..), monadBuilder)

-- Design Comments
--
-- # Designing Zip functions
--
-- * Zip will not work on infinite length linear streams
-- * On finite length streams, we need to ask about how we consume
-- the remainder of the shorter stream and if the streams are equal,
-- what we do with the two end-of-stream values of type 'r'.
-- * There are two options that seem to make sense: (1) return the remainder or
-- the two 'r's, and (2) use 'effects' to consume the remainder and return the
-- two 'r's.
-- * We chose the last one since it most closely matches the Unrestricted
-- original version.


-- # Zips and Unzips
-------------------------------------------------------------------------------

zipWith :: Control.Monad m =>
  (a -> b -> c) ->
  Stream (Of a) m r1 #->
  Stream (Of b) m r2 #->
  Stream (Of c) m (r1,r2)
zipWith f st1 st2 = st1 & \case
  Effect ms -> Effect $ ms >>= (\s -> return $ zipWith f s st2)
  Return r1 -> Effect $ (effects st2) >>= (\r2 -> return $ Return (r1, r2))
  Step (a :> as) -> st2 & \case
    Effect ms -> Effect $ ms >>= (\s -> return $ zipWith f (Step (a :> as)) s)
    Return r2 -> Effect $ (effects as) >>= (\r1 -> return $ Return (r1, r2))
    Step (b :> bs) -> Step $ (f a b) :> zipWith f as bs
  where
    Builder{..} = monadBuilder

zip :: Control.Monad m =>
  Stream (Of a) m r1 #->
  Stream (Of b) m r2 #->
  Stream (Of (a,b)) m (r1,r2)
zip = zipWith (,)

zipWith3 :: Control.Monad m =>
  (a -> b -> c -> d) ->
  Stream (Of a) m r #->
  Stream (Of b) m r #->
  Stream (Of c) m r #->
  Stream (Of d) m (r,r,r)
zipWith3 f s1 s2 s3 = s1 & \case
  Effect ms -> Effect $ ms >>= \s -> return $ zipWith3 f s s2 s3
  Return r1 -> Effect $ do
    r2 <- effects s2
    r3 <- effects s3
    return $ Return (r1,r2,r3)
  Step (a :> as) -> s2 & \case
    Effect ms -> Effect $
      ms >>= \s -> return $ zipWith3 f (Step (a :> as)) s s3
    Return r2 -> Effect $ do
      r1 <- effects as
      r3 <- effects s3
      return $ Return (r1,r2,r3)
    Step (b :> bs) -> s3 & \case
      Effect ms -> Effect $
        ms >>= \s -> return $ zipWith3 f (Step (a :> as)) (Step (b :> bs)) s
      Return r3 -> Effect $ do
        r1 <- effects as
        r2 <- effects bs
        return $ Return (r1,r2,r3)
      Step (c :> cs) -> Step $ (f a b c) :> zipWith3 f as bs cs
  where
    Builder{..} = monadBuilder

zip3 :: Control.Monad m =>
  Stream (Of a) m r #->
  Stream (Of b) m r #->
  Stream (Of c) m r #->
  Stream (Of (a, b, c)) m (r,r,r)
zip3 = zipWith3 (,,)

unzip :: Control.Monad m =>
  Stream (Of (a, b)) m r #-> Stream (Of a) (Stream (Of b) m) r
unzip = undefined

partitionEithers :: Control.Monad m =>
  Stream (Of (Either a b)) m r #-> Stream (Of a) (Stream (Of b) m) r
partitionEithers = undefined

partition :: Control.Monad m =>
  (a -> Bool) -> Stream (Of a) m r #-> Stream (Of a) (Stream (Of a) m) r
partition = undefined


-- # Merging
-------------------------------------------------------------------------------

merge :: (Control.Monad m, Ord a) =>
  Stream (Of a) m r #-> Stream (Of a) m s #-> Stream (Of a) m (r, s)
merge = mergeBy compare

mergeOn :: (Control.Monad m, Ord b) =>
  (a -> b) ->
  Stream (Of a) m r #->
  Stream (Of a) m s #->
  Stream (Of a) m (r, s)
mergeOn f = mergeBy (\x y -> compare (f x) (f y))

mergeBy :: Control.Monad m =>
  (a -> a -> Ordering) ->
  Stream (Of a) m r #->
  Stream (Of a) m s #->
  Stream (Of a) m (r, s)
mergeBy comp s1 s2 = s1 & \case
  Return r -> Effect $ effects s2 >>= \s -> return $ Return (r, s)
  Effect ms -> Effect $
    ms >>= \s1' -> return $ mergeBy comp s1' s2
  Step (a :> as) -> s2 & \case
    Return s -> Effect $ effects as >>= \r -> return $ Return (r, s)
    Effect ms -> Effect $
      ms >>= \s2' -> return $ mergeBy comp (Step (a :> as)) s2'
    Step (b :> bs) -> case comp a b of
      LT -> Step (a :> Step (b :> mergeBy comp as bs))
      _ -> Step (b :> Step (a :> mergeBy comp as bs))
  where
    Builder{..} = monadBuilder


