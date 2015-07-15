-module(loader).

-compile(export_all).

-define(DEFAULT_FILE, "var/data.csv").
-define(DEFAULT_HEADER, "var/header.csv").
%% TODO:
%%  - add validations via 'proplists' before sending to proplists_mod
%%  - add getters
%%  - add proper error handling
%%  - add help functions

%% ====================================================================
%% Public API
%% ====================================================================

%% escript Entry point

opt_spec_list() -> [
        { file, $f, "file", {string, ?DEFAULT_FILE}, "Zombie Data (default: var/data.csv)"},
        { header, $h, "header", {string, ?DEFAULT_HEADER}, "Zombie Data Header (default: var/header.csv)"}
    ].

main(RawArgs) ->
    Args = parse_args(RawArgs),
    %%io:format("Args:~p\n", [Args]).
    case catch(process_args(Args)) of
        ok ->
            ok;
        Error ->
            io:format("ERROR: Uncaught error in config: ~p\n", [Error]),
            io:format("ERROR: With Args: ~p\n", [Args])
    end.

help() ->
    getopt:usage(opt_spec_list(), "loader"),
    halt(1).

%=============== COMBINE parse_args and process_args =====================%

parse_args(RawArgs) ->
    OptSpecList = opt_spec_list(),
    case getopt:parse(OptSpecList, RawArgs) of
        {ok, Args} ->
            Args;
        {error, {Reason, Data}} ->
            io:format("~p: ~p\n", [Reason, Data]),
            help()
    end.

process_args({Options, Values}) ->
    File = proplists:get_value(file, Options),
    Header = proplists:get_value(header, Options),
    io:format("File: ~p, Header: ~p, Values: ~p", [File, Header, Values]),

    {ok, Pid} = riakc_pb_socket:start_link("127.0.0.1", 10017),
    register(riak, Pid),
    {ok, Headers} = get_csv_line(Header),
    parse_csv({File, Headers});

process_args(Args) ->
    io:format("Invalid arguments: ~p\n", [Args]),
    help().

get_csv_line(Header) ->
  Parser = csv:binary_reader(Header),
  case csv:next_line(Parser) of
    {row, Line, _Id} -> { ok, [ list_to_binary(L) || L <- Line ] };
    Error -> {error, Error}
  end.

parse_csv({File,Headers}) ->
  Parser = csv:binary_reader(File, [{annotation, true}]),
  parse_csv(Parser, Headers, csv:next_line(Parser) ).

parse_csv(_Parser, _Headers, eof) ->
  ok;
parse_csv(Parser, Headers, {annotation, {Key, Value}}) ->
  io:format("~p: ~p ~n", [Key, Value]),
  parse_csv(Parser, Headers, csv:next_line(Parser));
parse_csv(Parser, Headers, {row, Line, _Id}) ->
  Zipped = lists:zip(Headers, [ list_to_binary(L) || L <- Line ]),
  save_json(Zipped),
  parse_csv(Parser, Headers, csv:next_line(Parser));
parse_csv(_Parser, _Headers, Whut) ->
  io:format("Error: Unknown result: ~p", [Whut]).


save_json(Zipped) ->
  %io:format("Riak: ~p", [whereis(riak)]),
  pong = riakc_pb_socket:ping(riak),
  %io:format("~p", [Json]).
  %Json = jsx:encode(Zipped),
  {<<"NationalID">>, Key} = lists:keyfind(<<"NationalID">>, 1, Zipped),
  io:format("Key: ~p~n",[Key]),
  Obj = riakc_obj:new({<<"default">>,<<"zombies">>}, Key, Zipped),
  riakc_pb_socket:put(riak, Obj).

    % Parser = csv:binary_reader(File, [{annotation, true}]),
    % case csv:next_line(Parser) of
    %      {row, Line, Id} ->
    %         io:format("~p: ~p ~n", [Id, Line]);
    %      {annotation, {Key, Value}} ->
    %           io:format("~p: ~p ~n", [Key, Value]);
    %      eof ->
    %          io:format("End of csv-file ~n")
    % end.

% get_file_content(File) ->
% %get_tokens_and_proplist(File) ->
%     Binary = try file:read_file(File) of
%         { ok, B } -> B
%     catch
%         ReadType:ReadError ->
%             io:format("Caught ~p: ~p\n", [ ReadType, ReadError ])
%     end,
%     binary_to_list(Binary).
