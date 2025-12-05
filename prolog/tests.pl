% tests.pl - Regression checks for Popper Prolog rewrite

:- begin_tests(popper).

:- use_module(popper).

addlast_options([ max_literals(3),
                  max_models(200),
                  clingo_timeout(30),
                  timeout(30),
                  skip_duplicates(true)
                ]).

test(addlast_complete_program, [nondet]) :-
    addlast_options(Opts),
    popper:popper('examples/addlast', Opts, Program, outcome(all, none)),
    popper:program_clauses(Program, Clauses),
    assertion(Clauses \= []),
    assertion(( member(Clause, Clauses), sub_atom(Clause, _, _, _, 'last') )),
    !.

test(addlast_no_duplicate_programs, [nondet]) :-
        addlast_options(Opts),
        select(max_models(_), Opts, OptsRest),
        OptsLimited = [max_models(50)|OptsRest],
        findall(SortedClauses,
                        ( popper:popper('examples/addlast', OptsLimited, Program, _),
                            popper:program_clauses(Program, Clauses),
                            sort(Clauses, SortedClauses)
                        ),
                        ClauseSets),
        sort(ClauseSets, UniqueSets),
        length(ClauseSets, L1),
        length(UniqueSets, L2),
        assertion(L1 =:= L2).

:- end_tests(popper).

run_tests :-
    run_tests([popper]).
