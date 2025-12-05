% order.pl - Clause ordering utilities for Popper Prolog rewrite

:- module(order,
    [ unordered_to_ordered/2
    ]).

:- use_module(library(lists)).
:- use_module(library(ordsets)).

:- use_module(core).

unordered_to_ordered(unordered_program(Clauses, Before), OrderedProgram) :-
    maplist(order_clause, Clauses, OrderedClauses),
    core:make_ordered_program(OrderedClauses, Before, OrderedProgram).

order_clause(unordered_clause([Head], BodyLits, Min), OrderedClause) :-
    core:literal_inputs(Head, Inputs),
    Head = literal(Predicate, _, _, _),
    selection_closure(Predicate, Inputs, BodyLits, [], OrderedBody),
    core:make_ordered_clause([Head], OrderedBody, Min, OrderedClause).

selection_closure(_, _, [], Acc, Ordered) :-
    reverse(Acc, Ordered).
selection_closure(HeadPred, Grounded, Remaining, Acc, Ordered) :-
    select_groundable_literal(HeadPred, Grounded, Remaining, Literal, Rest),
    core:literal_outputs(Literal, Outputs),
    ord_union(Grounded, Outputs, Grounded1),
    selection_closure(HeadPred, Grounded1, Rest, [Literal|Acc], Ordered).

select_groundable_literal(HeadPred, Grounded, Remaining, Literal, Rest) :-
    groundable_literals(Grounded, Remaining, Candidates),
    (   select_non_recursive(HeadPred, Candidates, Literal)
    ;   select_recursive(HeadPred, Candidates, Literal)
    ),
    select(Literal, Remaining, Rest), !.
select_groundable_literal(_, Grounded, Remaining, _, _) :-
    throw(error(cannot_ground(Remaining, Grounded), _)).

groundable_literals(Grounded, Remaining, Candidates) :-
    findall(Literal,
        ( member(Literal, Remaining), literal_grounded(Grounded, Literal) ),
        Candidates).

literal_grounded(Grounded, Literal) :-
    core:literal_inputs(Literal, Inputs),
    ord_subset(Inputs, Grounded).

select_non_recursive(_, [], _) :- fail.
select_non_recursive(HeadPred, [Literal|Rest], Choice) :-
    Literal = literal(Pred, _, _, _),
    (   Pred \= HeadPred
    ->  Choice = Literal
    ;   select_non_recursive(HeadPred, Rest, Choice)
    ).

select_recursive(HeadPred, Candidates, Literal) :-
    member(Literal, Candidates),
    Literal = literal(HeadPred, _, _, _), !.
