%% @author Syed Ahmed
%% @doc Program to parse erlang files and build a cscope database.
-module(erlcscope).
-include("erlcscope.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([main/0]).

main()->
	{ok, Data} = file:read_file(?INPUT_FILE),
	Files = lists:sort(string:tokens(binary_to_list(Data), ?NEWLINE_SEP)),
	{ok, Db} = file:open(?OUTPUT_FILE,[write]),
	init_symbol_db(Db,0),
	lists:foreach(fun(Fname) -> 
		build_symbol_db_from_file(Db,Fname) end, 
	Files),
	write_symbol_trailer_to_db(Db, Files).

%% ====================================================================
%% Parsing and processing functions
%% ====================================================================

build_symbol_db_from_file(Db, SrcFile) ->
	{ok, FileData} = file:read_file(SrcFile),
	Lines = split_data_to_lines(binary_to_list(FileData)),
	State = #state{db=Db,data=Lines},
	write_symbol_to_db(?FILE_MARK, SrcFile, 0, 0, State),
	{ok, ParseTree} = epp_dodger:parse_file(SrcFile),
	traverse_tree([ParseTree],State).


traverse_tree(TreeList, S=#state{}) ->
	lists:foreach( 
	fun(NodeList) ->
		lists:foreach(fun(Node) ->
			%io:format("Node ~p~n", [Node]),
			{NewNode, NewState} = case erl_syntax:type(Node) of
						  atom -> process_atom(Node, S);
						  %function -> process_function(Node);
						  _ -> {erl_syntax:subtrees(Node), S}
					  end,
					  traverse_tree(NewNode,NewState)
    	end, NodeList)
	end, TreeList).

process_atom(Node, S=#state{}) ->
	AtomName = erl_syntax:atom_name(Node),
	LineNo = erl_syntax:get_pos(Node),
	%Line = string:strip(lists:nth(S#state.line_no + 1, S#state.data)),
	Line = lists:nth(LineNo, S#state.data),
	% search pos in line
	Pos = string:str( string:sub_string(Line, S#state.pos+1), AtomName),
	% search pos in line
	Pos = string:str( string:sub_string(Line, S#state.pos+1), AtomName),
	%io:format("Got atom ~p at pos ~p in line no ~p : ~s~n",[AtomName, Pos, LineNo, Line]),
	NewState = write_symbol_to_db(?SYMBOL_MARK, AtomName, LineNo, Pos, S),
	{[], NewState}.

%% ====================================================================
%% Functions for writing to the file
%% ====================================================================

init_symbol_db(Db, TrailerOffset ) ->
	{ok, Cwd} = file:get_cwd(),
	Header = lists:flatten(io_lib:format("cscope ~s ~s -c ~10..0b~n", 
									[?CSCOPE_VERSION, Cwd,TrailerOffset])),
	io:format(Db,"~s",[Header]).

%% Format For File      
%% <file mark><file path>
%% <empty line>

write_symbol_to_db(?FILE_MARK, Fname, _LineNo , _Pos , S=#state{}) ->
	io:format(S#state.db,"~s~s~n~n", [?FILE_MARK, Fname]);
	
%% Format for other symbols
%% <line number><blank><non-symbol text>
%% <optional mark><symbol>
%% <non-symbol text>
%% repeat above 2 lines as necessary
%% <empty line>
%% Leading and trailing white space in  the  source  line  is
%% removed. Tabs are changed to blanks, and multiple blanks
%% are squeezed to a single  blank,  even  in  character  and
%% string  constants.
%% whitespaces are already removed when saving the lines in 
%% the state

write_symbol_to_db(Type, Name, LineNo, Pos, S=#state{}) ->
	Fd = S#state.db,
	Line = lists:nth(LineNo, S#state.data),
	
	{NewLine, NewPos} = case LineNo == S#state.line_no  of
		  false ->  
 			 % we have moved to new line, complete the old line
	     	 % and write the new line
			 
			 case S#state.line_no  of
				 0 -> ok;
				 _ ->
					OldLine = lists:nth(S#state.line_no, S#state.data),
					io:format(Fd,"~s~n~n", [string:substr(OldLine,S#state.pos)])
			end,
						
			% write new line number with non-symbol data
			NonSymbolData = string:substr(Line, S#state.pos, Pos),
			io:format(Fd,"~b ~s~n",[LineNo,NonSymbolData]),
			io:format(Fd,"~s~s~n",[Type,Name]),
			{LineNo, Pos + length(Name)};
		  true ->
		    % we are in the same line, we will just update the position
			NonSymbolData = string:substr(Line, S#state.pos, Pos),
			io:format(Fd,"~s~n",[NonSymbolData]),
			io:format(Fd,"~s~s~n",[Type,Name]),
			{LineNo, Pos + length(Name)}
	end,
	io:format("old line ~b old pos ~b Newline ~b, newpos ~b linelen ~b ~n",[S#state.line_no, S#state.pos,NewLine,NewPos,length(Line)]),
	S#state{line_no=NewLine, pos=NewPos}.
	%io:format("type ~s name ~s pos ~s line ~s state ~p~n",[Type, Name, LineNo, Pos, S]),
	%S.
	

write_symbol_trailer_to_db(Db,Files) ->
   	io:format(Db, "~s~n", [?SYMBOL_END]),
	TrailerOffset = filelib:file_size(?OUTPUT_FILE),
	io:format(Db, "1~n.~n0~n~p~n~p~n", [length(Files), lists:flatlength(Files) + length(Files)]),
	lists:foreach(fun(Fname) -> io:format(Db,"~s~n",[Fname]) end, Files),
	file:close(Db),
	{ok , Db2} = file:open(?OUTPUT_FILE, [read,write]),
	io:format("Trailer offset ~b",[TrailerOffset]),
	init_symbol_db(Db2, TrailerOffset),
	file:close(Db2).


%% ====================================================================
%% Other utility functions
%% ====================================================================



split_data_to_lines(Data) ->
	split_data_to_lines(Data,[],[]).

split_data_to_lines([],Acc,Out)->
	lists:reverse([Acc|Out]);

split_data_to_lines([Ch|Rem], Acc, Out) ->
	case Ch == $\n of
		true -> split_data_to_lines(Rem, [], [ lists:reverse(remove_spaces(Acc)) | Out ]);
		false -> split_data_to_lines(Rem, [Ch|Acc], Out )
	end.

remove_spaces(String) ->
	re:replace(String, "\\s+", " ", [global, {return, list}]).