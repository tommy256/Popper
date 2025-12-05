% generate.pl - Transform Clingo models into Popper program structures

:- module(generate,
    [ unordered_program_from_model/2
    ]).

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(pcre)).

:- use_module(core).

%% unordered_program_from_model(+ModelAtoms, -Program)
%  Convert a list of atom strings (as returned by solver:clingo_model/3)
%  into an unordered_program term.
unordered_program_from_model(ModelAtoms, Program) :-
    foldl(classify_atom,
          ModelAtoms,
          state([], [], [], [], []),
          state(BeforePairs, MinPairs, Directions, HeadData, BodyData)),
    build_direction_map(Directions, DirectionMap),
    build_heads(HeadData, DirectionMap, HeadLits),
    build_bodies(BodyData, DirectionMap, BodyMap),
    build_min_map(MinPairs, MinMap),
    assemble_clauses(HeadLits, BodyMap, MinMap, Clauses),
    build_before_map(BeforePairs, BeforeMap),
    core:make_unordered_program(Clauses, BeforeMap, Program).

classify_atom(String, State0, State) :-
    (   parse_before(String, C1, C2)
    ->  State0 = state(Before, Min, Dir, Head, Body),
        ord_add_element(Before, C1-C2, Before1),
        State = state(Before1, Min, Dir, Head, Body)
    ;   parse_min_clause(String, C, MinVal)
    ->  State0 = state(Before, Min, Dir, Head, Body),
        ord_add_element(Min, C-MinVal, Min1),
        State = state(Before, Min1, Dir, Head, Body)
    ;   parse_direction(String, Pred, Idx, DirTag)
    ->  State0 = state(Before, Min, Dir, Head, Body),
        State = state(Before, Min, [Pred-Idx-DirTag|Dir], Head, Body)
    ;   parse_head_literal(String, Clause, Pred, Arity, Vars)
    ->  State0 = state(Before, Min, Dir, Head, Body),
        State = state(Before, Min, Dir, [head(Clause, Pred, Arity, Vars)|Head], Body)
    ;   parse_body_literal(String, Clause, Pred, Arity, Vars)
    ->  State0 = state(Before, Min, Dir, Head, Body),
        State = state(Before, Min, Dir, Head,
                      [body(Clause, Pred, Arity, Vars)|Body])
    ;   State = State0
    ).

parse_before(String, C1, C2) :-
    re_matchsub('^before\\((\\d+),(\\d+)\\)$', String, Dict, []),
    number_string(C1, Dict.1),
    number_string(C2, Dict.2).

parse_min_clause(String, Clause, Min) :-
    re_matchsub('^min_clause\\((\\d+),(\\d+)\\)$', String, Dict, []),
    number_string(Clause, Dict.1),
    number_string(Min, Dict.2).

parse_direction(String, Pred, Index, Mode) :-
    re_matchsub('^direction\\(([a-zA-Z0-9_]+),(\\d+),(in|out|unknown)\\)$',
                String, Dict, []),
    atom_string(Pred, Dict.1),
    number_string(Index, Dict.2),
    atom_string(Mode, Dict.3).

parse_head_literal(String, Clause, Pred, Arity, Vars) :-
    parse_literal('head_literal', String, Clause, Pred, Arity, Vars).

parse_body_literal(String, Clause, Pred, Arity, Vars) :-
    parse_literal('body_literal', String, Clause, Pred, Arity, Vars).

parse_literal(Functor, String, Clause, Pred, Arity, Vars) :-
    format(string(Pattern), '^~w\\((\\d+),([a-zA-Z0-9_]+),(\\d+),\\((.*)\\)\\)$', [Functor]),
    re_matchsub(Pattern, String, Dict, []),
    number_string(Clause, Dict.1),
    atom_string(Pred, Dict.2),
    number_string(Arity, Dict.3),
    split_vars(Dict.4, Vars).

split_vars(Raw, Vars) :-
    split_string(Raw, ',', ' ', Parts0),
    exclude(=(""), Parts0, Parts),
    maplist(number_string, Vars, Parts).

build_direction_map(Triples, Map) :-
    foldl(add_direction, Triples, directions{}, Map).

add_direction(Pred-Idx-Mode, Map0, Map) :-
    (   get_dict(Pred, Map0, PredMap0)
    ->  true
    ;   PredMap0 = _{}
    ),
    PredMap = PredMap0.put(Idx, Mode),
    Map = Map0.put(Pred, PredMap).

build_heads(HeadData, DirMap, HeadLits) :-
    maplist(head_literal_term(DirMap), HeadData, HeadPairs),
    sort(HeadPairs, HeadLits).

head_literal_term(DirMap, head(Clause, Pred, Arity, VarsIndices), Clause-Literal) :-
    build_literal(Pred, Arity, VarsIndices, DirMap, Literal).

build_bodies(BodyData, DirMap, BodyMap) :-
    foldl(body_literal_term(DirMap), BodyData, bodies{}, BodyMap).

body_literal_term(DirMap, body(Clause, Pred, Arity, VarsIndices), Map0, Map) :-
    build_literal(Pred, Arity, VarsIndices, DirMap, Literal),
    (   get_dict(Clause, Map0, Existing)
    ->  NewBody = [Literal|Existing]
    ;   NewBody = [Literal]
    ),
    Map = Map0.put(Clause, NewBody).

build_literal(PredName, Arity, VarsIndices, DirMap, Literal) :-
    maplist(core:index_variable, VarsIndices, Vars),
    directions_for(PredName, Arity, DirMap, Modes),
    Predicate = pred(PredName, Arity),
    core:make_literal(Predicate, Vars, Modes, true, Literal).

build_min_map(Pairs, Map) :-
    foldl(add_min, Pairs, mins{}, Map).

add_min(Clause-Min, Map0, Map) :-
    Map = Map0.put(Clause, Min).

assemble_clauses(HeadLits, BodyMap, MinMap, Clauses) :-
    findall(ClauseId,
        member(ClauseId-_, HeadLits),
        ClauseIds0),
    sort(ClauseIds0, ClauseIds),
    maplist(make_clause_term(HeadLits, BodyMap, MinMap), ClauseIds, Clauses).

make_clause_term(HeadLits, BodyMap, MinMap, ClauseId, Clause) :-
    memberchk(ClauseId-HeadLiteral, HeadLits),
    (   get_dict(ClauseId, BodyMap, BodyList0)
    ->  sort(BodyList0, BodyList)
    ;   BodyList = []
    ),
    (   get_dict(ClauseId, MinMap, Min)
    ->  true
    ;   Min = 0
    ),
    core:make_unordered_clause([HeadLiteral], BodyList, Min, Clause).

build_before_map(Pairs, Map) :-
    foldl(add_before, Pairs, before{}, Map).

add_before(C1-C2, Map0, Map) :-
    (   get_dict(C1, Map0, Existing)
    ->  ord_add_element(Existing, C2, Updated)
    ;   ord_add_element([], C2, Updated)
    ),
    Map = Map0.put(C1, Updated).

% default unknown for missing directions
directions_for(Pred, Arity, DirMap, Modes) :-
        (   get_dict(Pred, DirMap, PredMap)
        ->  true
        ;   PredMap = _{}
        ),
        MaxIndex is Arity - 1,
        findall(Mode,
                ( between(0, MaxIndex, Index),
                    (   get_dict(Index, PredMap, Mode0)
                    ->  Mode = Mode0
                    ;   Mode = unknown
                    )
                ),
                Modes).
