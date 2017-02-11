module Sem_cont
where

import Prelude hiding (length, take, replicate)
import Data.Sequence
import Data.Maybe
import AST

data State = State { stack :: Seq Value, result :: Value, labels :: [(Int,ST)] }

type ST = State -> State
type Cont = ST -> ST

val :: Value -> ST
val x (State stack _ labels) = State stack x labels

put :: Int -> Value -> ST
put i x (State stack _ labels) = State (update i x stack) x labels

get :: Int -> ST
get i (State stack _ labels) = State stack (index stack i) labels

enter :: Int -> ST
enter n (State stack x labels) = State (stack >< replicate n undefined) x labels

leave :: Int -> ST
leave n (State stack x labels) = State (take (length stack - n) stack) x labels

-- can't use pattern matching on the argument in these functions
-- as this will force strict evaluation of the state
(<@) :: State -> [(Int, ST)] -> State
st <@ tag = State (stack st) (result st) (tag++labels st)

(>@<) :: State -> State -> State
st >@< st' = st <@ labels st'

(=:@) :: State -> State -> State
st =:@ tag = State (stack st) (result st) (labels tag)

(>:) :: Cont -> (Value->ST) -> Cont
--(>:) f g k = f (\st->k (g (result st) st))
(>:) f g = f >:: (\x->(.g x))

(>::) :: Cont -> (Value->Cont) -> Cont
(>::) f g k = f (\st->g (result st) k st)

sem :: Expr -> Cont
sem Skip         = (.val undefined)
sem (Const i)    = (.val i)
sem (Var i := e) = sem e >: put i
sem (Val (Var i))= (.get i)
sem (If a b c)   = sem a >:: \x k st->(sem $ if x/=0 then b else c) k st =:@ (sem b k st >@< sem c k st)
sem (While a b)  = sem (If a (b:::While a b) Skip)
sem (DyOp f a b) = sem a >:: \x->sem b >: \y-> val $ f x y
sem (UnOp f a)   = sem a >: \x->val $ f x
sem (a ::: b)    = sem a . sem b

sem (Goto i)     = \k st->fromJust (lookup i (labels st)) st =:@ k st
sem (Label i)    = \k->(<@ [(i,k)]).k

-- this is too simplistic
sem (Scope n a)  = \k->sem a (k.leave n).enter n

eval_once :: Expr -> Value
eval_once e = result $ sem e id initial
   where initial = State empty undefined []

eval' :: Expr -> Value
eval' e = result $ sem e id (initial =:@ sem e id initial)
   where initial = State empty undefined []

eval :: Expr -> Value
eval e = result $ sem e id (initial =:@ sem e id illegal)
   where initial = State empty undefined []
         illegal = State undefined undefined []