{-# language TypeFamilyDependencies, GADTs, TypeInType, TypeOperators,
  TypeApplications, MultiParamTypeClasses, FlexibleInstances, FlexibleContexts,
  AllowAmbiguousTypes, ScopedTypeVariables, UndecidableInstances #-}

module Test.StrictCheck.Variadic where

import Data.Kind
import Generics.SOP
import Generics.SOP.NP


-------------------------------------------------
-- Manipulating the types of curried functions --
-------------------------------------------------

-- Given a function, return a list of all its argument types
type family Args (f :: *) :: [*] where
  Args (a -> rest) = a : Args rest
  Args x           = '[]

-- Given a list of argument types and a "rest" of type return a curried function
type family WithArgs (args :: [*]) (rest :: *) :: * where
  WithArgs '[]        rest = rest
  WithArgs (a : args) rest = a -> WithArgs args rest

-- Given a list of argument types matching some prefix of the arguments of a
-- curried function type, remove those arguments from the function type
type family WithoutArgs (args :: [*]) (f :: *) :: * where
  WithoutArgs '[]        rest        = rest
  WithoutArgs (a : args) (a -> rest) = WithoutArgs args rest

-- Strip all arguments from a function type, yielding its (non-function) result
type Result f = WithoutArgs (Args f) f


-------------------------------------------------------
-- Collapsing curried functions into data structures --
-------------------------------------------------------

-- A Function represents some n-ary function, currySomed into a pseudo-list
data Function (args :: [*]) (res :: *) where
  Res :: res -> Function '[] res
  Arg :: (a -> Function args res) -> Function (a : args) res

instance Functor (Function args) where
  fmap f (Res res)    = Res (f res)
  fmap f (Arg lambda) = Arg (\a -> fmap f (lambda a))

instance Applicative (Function '[]) where
  pure = Res
  Res f <*> Res a = Res (f a)

instance Applicative (Function args) => Applicative (Function (a : args)) where
  pure = Arg . const . pure
  Arg l <*> Arg m = Arg (\a -> l a <*> m a)

-- It's also a monad but the instance is really complicated to write & honestly
-- I don't think it's very useful. Left as an exercise to the reader.

-- We can apply a Function to a matching list of arguments
applyFunction :: Function args res -> NP I args -> res
applyFunction (Res res)    Nil           = res
applyFunction (Arg lambda) (I a :* rest) = applyFunction (lambda a) rest

-- A nice infix notation for applying a Function
($$) :: Function args res -> NP I args -> res
($$) = applyFunction

-- Additionally, we can transform a function from a heterogeneous list to some
-- result into a Function.
toFunction :: SListI xs => (NP I xs -> res) -> Function xs res
toFunction f = go (pure_NP (K ())) f
  where
    -- The use of CPS style here prevents quadratic blowup
    go :: NP (K ()) xs -> (NP I xs -> res) -> Function xs res
    go Nil       k = Res (k Nil)
    go (_ :* ts) k = Arg (\a -> go ts (k . (I a :*)))


--------------------------------------
-- Partial currying, Functionically --
--------------------------------------

-- | The Curry class lets us embed a function in a Function, or extract it
-- This is yet another "inductive typeclass" definition
class Curry (args :: [*]) (function :: *) where
   curryFunction   :: function -> Function args (WithoutArgs args function)
   uncurryFunction :: Function args (WithoutArgs args function) -> function

-- | We can always move back and forth between a (Res x) and an x
instance Curry '[] x where
  curryFunction        x  = Res x
  uncurryFunction (Res x) =     x

-- | If we know how to move back and forth between a Function on args & rest and
-- its corresponding function, we can do the same if we add one more argument to
-- the front of the list and to its corresponding function
instance Curry args rest => Curry (a : args) (a -> rest) where
  curryFunction        f  = Arg $ \a -> curryFunction   (f a)
  uncurryFunction (Arg f) =       \a -> uncurryFunction (f a)


--------------------------------------------------------
-- Variadic currying/uncurrying, aka (un)curryAll-ing --
--------------------------------------------------------

curryAll :: Curry (Args function) function
         => function
         -> (NP I (Args function) -> Result function)
curryAll = applyFunction . curryFunction

uncurryAll :: (Curry (Args function) function, SListI (Args function))
           => (NP I (Args function) -> Result function)
           -> function
uncurryAll = uncurryFunction . toFunction