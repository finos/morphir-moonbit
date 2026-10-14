module Parity.Signatures.Functions exposing (..)


constant : Int
constant =
    1


add : Int -> Int -> Int
add a b =
    a + b


swap : ( a, b ) -> ( b, a )
swap ( a, b ) =
    ( b, a )


ignore : a -> Int
ignore _ =
    0


unit : () -> Int
unit () =
    0


leading : Int -> Int -> Int
leading =
    \a b -> a + b


partial : Int -> Int -> Int
partial a =
    \b -> a + b


paren : a -> b -> a
paren a =
    (\x -> a)


tupleLambda : Int -> ( Int, Int ) -> Int
tupleLambda =
    \a ( b, c ) -> a + b + c


mixed : Int -> ( Int, Int ) -> Int -> Int
mixed a ( b, c ) d =
    a + b + c + d


increment : Int -> Int
increment =
    add 1
