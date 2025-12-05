% core.pl - Shared data structures and helpers for Popper Prolog rewrite

:- module(core,
        [ index_variable/2,
            make_literal/5,
            literal_inputs/2,
            literal_outputs/2,
            literal_unknowns/2,
            literal_code/2,
            make_unordered_clause/4,
            make_clause/4,
            make_unordered_program/3,
            make_ordered_clause/4,
            make_ordered_program/3
        ]).

:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).

index_variable(Index, var(Name)) :-
    must_be(nonneg, Index),
    Base is 65 + Index,
    char_code(Name, Base).

make_literal(Predicate, Arguments, Modes, Polarity,
         literal(Predicate, Arguments, Modes, Polarity)).

literal_inputs(literal(_, Arguments, Modes, _), Inputs) :-
    collect_by_mode(Arguments, Modes, in, Inputs).

literal_outputs(literal(_, Arguments, Modes, _), Outputs) :-
    collect_by_mode(Arguments, Modes, out, Outputs).

literal_unknowns(literal(_, Arguments, Modes, _), Unknowns) :-
    collect_by_mode(Arguments, Modes, unknown, Unknowns).

literal_code(literal(pred(Name,_), Arguments, _, _), Code) :-
    maplist(argument_name, Arguments, ArgNames),
    atomic_list_concat(ArgNames, ',', ArgString),
    format(atom(Code), '~w(~w)', [Name, ArgString]).

make_unordered_clause(Head, Body, Min,
                      unordered_clause(Head, Body, Min)).

make_clause(Head, Body, Min,
            clause(Head, Body, Min)).

make_unordered_program(Clauses, Before,
                       unordered_program(Clauses, Before)).

make_ordered_clause(Head, Body, Min,
                    ordered_clause(Head, Body, Min)).

make_ordered_program(Clauses, Before, ordered_program(Clauses, Before)).

collect_by_mode(Arguments, Modes, Target, Set) :-
    findall(Arg,
        ( nth0(Index, Modes, Target), nth0(Index, Arguments, Arg) ),
        List),
    list_to_ord_set(List, Set).

argument_name(var(Name), Name).
