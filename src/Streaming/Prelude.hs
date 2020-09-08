{-| The names exported by this module are closely modeled on those in @Prelude@ and @Data.List@,
    but also on
    <http://hackage.haskell.org/package/pipes-4.1.9/docs/Pipes-Prelude.html Pipes.Prelude>,
    <http://hackage.haskell.org/package/pipes-group-1.0.3/docs/Pipes-Group.html Pipes.Group>
    and <http://hackage.haskell.org/package/pipes-parse-3.0.6/docs/Pipes-Parse.html Pipes.Parse>.
    The module may be said to give independent expression to the conception of
    Producer \/ Source \/ Generator manipulation
    articulated in the latter two modules. Because we dispense with piping and
    conduiting, the distinction between all of these modules collapses. Some things are
    lost but much is gained: on the one hand, everything comes much closer to ordinary
    beginning Haskell programming and, on the other, acquires the plasticity of programming
    directly with a general free monad type. The leading type, @Stream (Of a) m r@ is chosen to permit an api
    that is as close as possible to that of @Data.List@ and the @Prelude@.

    Import qualified thus:

> import Streaming
> import qualified Streaming.Prelude as S

    For the examples below, one sometimes needs

> import Streaming.Prelude (each, yield, next, mapped, print', stdoutLn', stdinLn)
> import Data.Function ((&))

   Other libraries that come up in passing are

> import qualified Control.Foldl as L -- cabal install foldl
> import qualified Pipes as P
> import qualified Pipes.Prelude as P
> import qualified System.IO as IO
> import qualified Prelude
> import qualified Prelude.Linear as Linear
> import Prelude.Linear (($), (.))
> import Data.Unrestricted.Linear
> import System.IO.Linear

Extensions used include

>>> :seti -XLinearTypes
>>> :seti -XQualifiedDo


     Here are some correspondences between the types employed here and elsewhere:

>               streaming             |            pipes               |       conduit       |  io-streams
> -------------------------------------------------------------------------------------------------------------------
> Stream (Of a) m ()                  | Producer a m ()                | Source m a          | InputStream a
>                                     | ListT m a                      | ConduitM () o m ()  | Generator r ()
> -------------------------------------------------------------------------------------------------------------------
> Stream (Of a) m r                   | Producer a m r                 | ConduitM () o m r   | Generator a r
> -------------------------------------------------------------------------------------------------------------------
> Stream (Of a) m (Stream (Of a) m r) | Producer a m (Producer a m r)  |
> --------------------------------------------------------------------------------------------------------------------
> Stream (Stream (Of a) m) r          | FreeT (Producer a m) m r       |
> --------------------------------------------------------------------------------------------------------------------
> --------------------------------------------------------------------------------------------------------------------
> ByteString m ()                     | Producer ByteString m ()       | Source m ByteString  | InputStream ByteString
> --------------------------------------------------------------------------------------------------------------------
>
-}
module Streaming.Prelude
  ( module Streaming.Consume
  , module Streaming.Interop
  , module Streaming.Many
  , module Streaming.Process
  , module Streaming.Produce
  , module Streaming.Type
  ) where

import Streaming.Consume
import Streaming.Interop
import Streaming.Many
import Streaming.Process
import Streaming.Produce
import Streaming.Type


