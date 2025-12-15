% solver.pl - Clingo integration for Popper Prolog rewrite

:- module(solver,
        [ clingo_model/3,    % +KbDir, +LiteralCount, -ModelAtoms
            clingo_model/4,    % +KbDir, +LiteralCount, +TimeLimit, -ModelAtoms
            clingo_models/3,   % +KbDir, +LiteralCount, -ListOfModelAtoms
            clingo_models/4    % +KbDir, +LiteralCount, +TimeLimit, -ListOfModelAtoms
        ]).

:- use_module(library(apply)).
:- use_module(library(error)).
:- use_module(library(http/json)).
:- use_module(library(process)).
:- use_module(library(readutil)).

%% clingo_model(+KbDir, +LiteralCount, -ModelAtoms)
%  Succeeds for the first model (if any) of the given literal count.
clingo_model(KbDir0, LiteralCount, ModelAtoms) :-
    clingo_models(KbDir0, LiteralCount, [ModelAtoms|_]).

%% clingo_model(+KbDir, +LiteralCount, +TimeLimit, -ModelAtoms)
%  As clingo_model/3 but imposing a time limit (seconds, 0 = no limit).
clingo_model(KbDir0, LiteralCount, TimeLimit, ModelAtoms) :-
    clingo_models(KbDir0, LiteralCount, TimeLimit, [ModelAtoms|_]).

%% clingo_models(+KbDir, +LiteralCount, -Models)
%  Obtain all available ASP models (as lists of atoms) for the given
%  literal count. Models is a list of witness Value lists extracted from
%  Clingo's JSON output. Fails if the instance is UNSAT.
clingo_models(KbDir0, LiteralCount, Models) :-
    clingo_models(KbDir0, LiteralCount, 0, Models).

%% clingo_models(+KbDir, +LiteralCount, +TimeLimit, -Models)
%  As clingo_models/3 but with an optional time limit (seconds) for Clingo.
clingo_models(KbDir0, LiteralCount, TimeLimit, Models) :-
    must_be(integer, LiteralCount),
    LiteralCount >= 0,
    must_be(integer, TimeLimit),
    TimeLimit >= 0,
    absolute_file_name(KbDir0, KbDir, [file_type(directory)]),
    alan_directory(AlanDir),
    directory_file_path(KbDir, 'modes.pl', ModesPath0),
    absolute_file_name(ModesPath0, ModesPath, [file_type(regular)]),
    directory_file_path(AlanDir, 'alan.pl', AlanProgram),
    process_args(AlanProgram, ModesPath, TimeLimit, Args),
    process_options(AlanDir, Options, In, Out, Err, PID),
    setup_call_cleanup(
        process_create(path(clingo), Args, Options),
        (
            send_literal_bound(In, LiteralCount),
            collect_stream(Out, Stdout),
            collect_stream(Err, Stderr)
        ),
        (
            close_stream_safe(In),
            close_stream_safe(Out),
            close_stream_safe(Err)
        )
    ),
    process_wait(PID, Status),
    (   memberchk(Status, [exit(10), exit(30)])
    ->  parse_models(Stdout, Models),
        Models \= []
    ;   Status == exit(20)
    ->  !, fail
    ;   Status == exit(11)
    ->  raise_timeout(TimeLimit)
    ;   permission_error(execute, clingo, status(Status-Stderr))
    ).

raise_timeout(TimeLimit) :-
    (   TimeLimit > 0
    ->  throw(error(time_limit_exceeded(TimeLimit),
                   context(clingo, 'Clingo time limit exceeded')))
    ;   throw(error(clingo_interrupted, context(clingo, 'Clingo interrupted')))
    ).

alan_directory(AlanDir) :-
    absolute_file_name('prolog/alan', AlanDir, [file_type(directory)]).

process_args(AlanProgram, ModesPath, TimeLimit, Args) :-
        Base = ['--outf=2', '--quiet=0', '--models=0'],
        (   TimeLimit > 0
        ->  format(atom(LimitAtom), '--time-limit=~g', [TimeLimit]),
                append(Base, [LimitAtom], Prefixed)
        ;   Prefixed = Base
        ),
        append(Prefixed, [AlanProgram, ModesPath, '-'], Args).

process_options(AlanDir,
                                [ cwd(AlanDir), stdin(pipe(In)), stdout(pipe(Out)), stderr(pipe(Err)),
                                    process(PID) ],
                                In, Out, Err, PID).

send_literal_bound(In, LiteralCount) :-
    format(In, "size_in_literals(~d).~n", [LiteralCount]),
    flush_output(In),
    close_stream_safe(In).

collect_stream(Stream, Content) :-
    read_string(Stream, _, Content).

parse_models(Stdout, Models) :-
    atom_string(Atom, Stdout),
    atom_json_dict(Atom, Dict, []),
    get_dict('Call', Dict, Calls),
    Calls = [Call|_],
    get_dict('Witnesses', Call, Witnesses),
        findall(Value,
                        ( member(Witness, Witnesses),
                            get_dict('Value', Witness, Value)
                        ),
                        Models).

close_stream_safe(Stream) :-
    (   var(Stream)
    ->  true
    ;   (   catch(close(Stream, [force(true)]), _, true)
        ->  true
        ;   true
        )
    ).
