%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ft=erlang ts=4 sw=4 et
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%  http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Live seeder is responsible for serving live stream data.
%% <p>description goes here</p>
%% @end

-module(ppspp_seeder).

-behaviour(gen_server).

%% -include("../include/ppspp.hrl").
-include("../include/ppspp_records.hrl").
-include("../include/swirl.hrl").
%% API
-export([start_link/1,
         start_link/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
%-spec start_link({atom(), hash()})
% TODO for injector the Role is seeder always !
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE,
                          [Args], []).

%% TODO implement init for this. 
start_link(Args, Swarm_Options) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE,
                          [Args, Swarm_Options], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([{Type, Swarm_ID, State_Table}]) ->
    {ok, State} = peer_core:init_server(Type, {Swarm_ID, State_Table}),
    {ok, State};

init([{_Type, _Swarm_ID}, _Swarm_Options]) ->
    %% TODO : discuss the data type for Swarm_Options 
    {ok, #peer{}}.

%%--------------------------------------------------------------------
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
%% Use call to receive new data becuse so the next data packets are not sent
%% untill the current one processed correctly.
%% TODO check this later
handle_call({newData, _Data}, _From, #peer{type=injector} = _State) ->
    %% TODO : check if the NCHUNKS_PER_SIG number of data packets have arrived
    %% and then create a new subtree and declare the new packets using HAVE
    %% messages in the swarm.
    ok;
handle_call(terminate, _From, State) ->
    {stop, normal, ok, State};

handle_call(Message, _From, State) ->
    ?WARN("peer: unexpected call: ~p~n", [Message]),
    {stop, {error, {unknown_call, Message}}, State}.

%%--------------------------------------------------------------------
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
%% Msg is dict of the type :
% [{channel,0},
%  {peer, [{endpoint,"127.0.0.1:54181"},
%          {peer,{127,0,0,1}},
%          {port,54181},
%          {transport,udp}]},
%  {messages, [{handshake, [{channel,1107349116}, {options, orddict()}]},
%              {have, [{have,Bin}]}]}
% ]
handle_cast(Msg, State) ->
    {ok, New_State} = peer_core:update_state(seeder, Msg, State),
    handle_msg(New_State#peer.type, Msg, New_State, []),
    %% TODO spwan the handle_msg and pass the decoded msg as argument.
    %% spwan(?MODULE, handle_msg, [{Type, Role}, Msg, State, []]),
    {noreply, New_State}.

%%--------------------------------------------------------------------
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Handle messages.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_msg(_, [], _State, _Reply) ->
    %% TODO send packed message to the listener
    %% lists:reverse(lists:flatten(Reply)).
    % ppspp_datagram:pack(Reply)
    % put the peer_state back into the ETS table.
    ok;

%%-----------------------------------------------------------------------------
%% HANDSHAKE : returns [HANDSHAKE, HAVE, HAVE ...]
%% Payload is expected to be an orddict.
handle_msg(Type, [{handshake, Payload} | Rest], State, Reply) ->
    {ok, Response} = ppspp_message:handle({Type, seeder},
                                          {handshake, Payload}, State),
    handle_msg(Type, Rest, State, [Response | Reply]);

%%-----------------------------------------------------------------------------
%% ACK : updates the state of the peer in State_Table for DATA received
handle_msg(Type, [{ack, Payload} | Rest], State, Reply) ->
    {ok, New_State} = ppspp_message:handle({Type, seeder},
                                           {ack, Payload}, State),
    handle_msg(Type, Rest, New_State, Reply);

%%-----------------------------------------------------------------------------
%% HAVE : seeder should not receive HAVE messages
handle_msg(Type, [{have,_Payload} | _Rest], State, _Reply) ->
    ?WARN("~p ~p: unexpected HAVE message ~n", [Type, seeder]),
    {noreply, State};

%%-----------------------------------------------------------------------------
%% INTEGRITY : should not be received,
handle_msg(Type, [{integrity, _Data} | Rest], State, Reply) ->
    ?WARN("~p ~p: unexpected INTEGRITY message ~n", [Type, seeder]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% NO implementation
handle_msg(Type, [{pex_resv4, _Data} | Rest], State, Reply) ->
    ?WARN("~p ~p: no implemention for PEX_RESV4 message ~n", [Type, seeder]),
    handle_msg(Type, Rest, State, Reply);
handle_msg(Type, [{pex_req, _Data} | Rest], State, Reply) ->
    ?WARN("~p ~p: no implementation for PEX_REQ message ~n", [Type, seeder]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% SIGNED_INTEGRITY : should not be received 
handle_msg(Type, [{signed_integrity, _Data} | Rest], State, Reply) ->
    ?WARN("~p ~p: unexpected SIGNED_INTEGRITY message ~n", [Type, seeder]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% REQUEST
handle_msg(Type, [{request, Payload} | Rest], State, Reply) ->
    {ok, Response} = ppspp_message:handle({Type, seeder},
                                          {request, Payload}, State) ,
    handle_msg(Type, Rest, State, [Response | Reply]);

%%-----------------------------------------------------------------------------
%% CANCEL : TODO kill the spawn process serving the DATA request for the peer.
handle_msg({_Type, _Role}, [{cancel, _Data} | _Rest], State, _Reply) ->
    {noreply, State};

%%-----------------------------------------------------------------------------
%% CHOKE : should not be received .
handle_msg(Type, [{choke, _Data} | Rest], State, Reply) ->
    ?WARN("~p ~p: unexpected choke message ~n", [Type, seeder]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% UNCHOKE : should not be received .
handle_msg(Type, [{unchoke, _Data} | Rest], State, Reply) ->
    ?WARN("live_seeder: unexpected UNCHOKE message ~n", []),
    handle_msg(Type, Rest, State, Reply);

%% currently no implementation
handle_msg(Type, [{pex_resv6, _Data} | Rest], State, Reply) ->
    ?WARN("~p ~p: unexpected PEX_RESV6 message ~n", [Type, seeder]),
    handle_msg(Type, Rest, State, Reply);
handle_msg(Type, [{pex_rescert, _Data} | Rest], State, Reply) ->
    ?WARN("~p ~p: unexpected PEX_RESCERT message ~n", [Type, seeder]),
    handle_msg(Type, Rest, State, Reply).
