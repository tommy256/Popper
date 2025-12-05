% solver.pl - Clingo integration for Popper Prolog rewrite

:- module(solver,
    [ clingo_model/3  % +KbDir, +LiteralCount, -ModelAtoms
    ]).

:- use_module(library(apply)).
:- use_module(library(error)).
:- use_module(library(http/json)).
:- use_module(library(process)).
:- use_module(library(readutil)).

%% clingo_model(+KbDir, +LiteralCount, -ModelAtoms)
%  Obtain one ASP model for the given knowledge base directory and
%  requested literal count. ModelAtoms is a list of atom strings as
%  provided by Clingo. Fails if the instance is UNSAT.
clingo_model(KbDir0, LiteralCount, ModelAtoms) :-
    must_be(integer, LiteralCount),
    LiteralCount >= 0,
    absolute_file_name(KbDir0, KbDir, [file_type(directory)]),
    alan_directory(AlanDir),
    directory_file_path(KbDir, 'modes.pl', ModesPath0),
    absolute_file_name(ModesPath0, ModesPath, [file_type(regular)]),
    directory_file_path(AlanDir, 'alan.pl', AlanProgram),
    process_args(AlanProgram, ModesPath, Args),
    process_options(AlanDir, LiteralCount, Options, In, Out, Err, PID),
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
    (   Status == exit(10)
    ->  parse_model(Stdout, ModelAtoms)
    ;   Status == exit(20)
    ->  !, fail
    ;   permission_error(execute, clingo, status(Status-Stderr))
    ).

alan_directory(AlanDir) :-
    absolute_file_name('popper/alan', AlanDir, [file_type(directory)]).

process_args(AlanProgram, ModesPath, [ '--outf=2', '--quiet=1'
                                    , AlanProgram, ModesPath, '-' ]).

process_options(AlanDir, LiteralCount,
                                [ cwd(AlanDir), stdin(pipe(In)), stdout(pipe(Out)), stderr(pipe(Err)),
                                    process(PID) ],
                                In, Out, Err, PID) :-
    _ = LiteralCount.

send_literal_bound(In, LiteralCount) :-
    format(In, "size_in_literals(~d).~n", [LiteralCount]),
    flush_output(In),
    close_stream_safe(In).

collect_stream(Stream, Content) :-
    read_string(Stream, _, Content).

parse_model(Stdout, ModelAtoms) :-
    atom_string(Atom, Stdout),
    atom_json_dict(Atom, Dict, []),
    get_dict('Call', Dict, Calls),
    Calls = [Call|_],
    get_dict('Witnesses', Call, Witnesses),
    Witnesses = [Witness|_],
    get_dict('Value', Witness, ModelAtoms).

close_stream_safe(Stream) :-
    (   var(Stream)
    ->  true
    ;   (   catch(close(Stream, [force(true)]), _, true)
        ->  true
        ;   true
        )
    ).
