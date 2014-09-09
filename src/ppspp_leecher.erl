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

-module(ppspp_leecher).

-behaviour(gen_server).

%% -include("../include/ppspp.hrl").
-include("../include/ppspp_records.hrl").
-include("../include/swirl.hrl").

-define(INTERVAL, 3000).

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
init([{static, Swarm_ID,_Swarm_Peers, State_Table}]) ->
    {ok, State} = peer_core:init_server(static, {Swarm_ID, State_Table}),
    %% TODO MAYBE send initial HANDSHAKE to all the peers
    {ok, State};

init([{live, Swarm_ID, Swarm_Peers, State_Table}]) ->
    {ok, State} = peer_core:init_server(live, {Swarm_ID, State_Table}),
    %% TODO send initial HANDSHAKE to all the peers in the live swarm to find
    %% out the latest munro.

    %% set timout of 30 seconds to check if Highest_Munro has been discovered.
    %% if not then kill the gen_server.
    erlang:send_after(?INTERVAL, self(), timeout),

    %% when the value of stable munro becomes 0 then munro associated to "have"
    %% key in server_date dict is considered the highest munro in swarm.
    %% NOTE : we expect 2/3 of the peer to respond with HAVE messages.
    %% TODO NOTE : this will fail if the Swarm Peers is empty list
    %% TODO discus the format for Swarm_Peers.
    Counter         = erlang:round((2/3)*erlang:length(Swarm_Peers)),
    New_Server_Data = orddict:store(stable_munro, Counter,
                                    State#peer.server_data),
    %%
    {ok, State#peer{server_data=New_Server_Data}};

init([{_Type, _Swarm_ID}, _Swarm_Options]) ->
    %% TODO : discuss the data type for Swarm_Options
    {ok, #peer{}}.

%%--------------------------------------------------------------------
%% @doc Handling call messages
%% @end
%%--------------------------------------------------------------------
handle_call(live_terminate, _From, State) ->
    {stop, normal, ok, State};

handle_call(Message, _From, State) ->
    ?WARN("leecher: unexpected call: ~p~n", [Message]),
    {stop, {error, {unknown_call, Message}}, State}.

%%--------------------------------------------------------------------
%% @doc Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(Msg, State) ->
    %% update the State with data of the peer from whom the Msg is recevied.
    {ok, New_State}     = peer_core:update_state(leecher, Msg, State),
    %% we can spwan concurrent process to process request but we can only spwan
    %% one process per peer !
    {ok, Updated_State} = handle_msg(New_State#peer.type, Msg, New_State, []),
    {noreply, Updated_State}.

%%--------------------------------------------------------------------
%% @doc Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
%% NOTE : ensure that timeout is received from self only !
handle_info(timeout, State) ->
    case State#peer.state of
        tune_in ->
            %% kill the gen_server so that supervisor restarts it.
            %% Note : if the gen_server doesn't start then only the leecher
            %% will be running.
            gen_server:call(self(), live_terminate);
        _Else   ->
            {noreply, State}
    end.

%%--------------------------------------------------------------------
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Handle messages.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_msg(_, [], State, _Reply) ->
    %% TODO send packed message to the listener.
    %% lists:reverse(lists:flatten(Reply)).
    %% ppspp_datagram:pack(Reply)
    %% store peer state back into the ETS table.
    peer_store:insert(State#peer.peer_table, {State#peer.peer,
                                              State#peer.peer_state}),
    {ok, State};

%%-----------------------------------------------------------------------------
%% HANDSHAKE
handle_msg(Type, [{handshake, Payload} | Rest], State, Reply) ->
    {ok, Response} = ppspp_message:handle({Type , leecher},
                                          {handshake, Payload}, State),
    handle_msg(Type, Rest, State, [Response | Reply]);

%%-----------------------------------------------------------------------------
%% ACK
handle_msg(Type, [{ack,_Payload} | Rest], State, Reply) ->
    ?WARN("~p ~p: unexpected ACK message ~n", [Type, leecher]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% HAVE
handle_msg(static, [{have, Payload} | Rest], State, Reply) ->
    %% TODO discuss how to prepare REQUEST msg to download DATA from multiple
    %% peers.
    {ok, Response} = ppspp_message:handle({static, leecher},
                                          {have, Payload}, State),
    handle_msg(static, Rest, State, [Response | Reply]);

handle_msg(live, [{have, Payload} | Rest], State, Reply) ->
    %% HAVE in case of live stream will contain latest munro as Payload.
    %% we store highest Payload in State and also store corresponding peers
    %% that sent those HAVE Msgs.
    {ok, New_State, Response} = ppspp_message:handle({live, leecher},
                                                     {have, Payload}, State),
    handle_msg(live, Rest, New_State, [Response | Reply]);

%%-----------------------------------------------------------------------------
%% INTEGRITY
handle_msg(Type, [{integrity, Payload} | Rest], State, Reply) ->
    {ok, New_State} = ppspp_message:handle({Type, leecher},
                                           {integrity, Payload}, State),
    handle_msg(Type, Rest, New_State, Reply);

%%
%% currently NO implementation
handle_msg(Type, [{pex_resv4, _Data} | Rest], State, Reply) ->
    ?WARN("live_seeder: unexpected pex_resv4 message ~n", []),
    handle_msg(Type, Rest, State, Reply);
handle_msg(Type, [{pex_req, _Data} | Rest], State, Reply) ->
    ?WARN("live_seeder: unexpected pex_req message ~n", []),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% Seeder should not receive signed_integrity message.
%% TODO incomplete
handle_msg(live, [{signed_integrity, Payload} | Rest], State, Reply) ->
    {ok, New_State} = ppspp_message:handle({live, leecher},
                                           {signed_integrity, Payload}, State),
    handle_msg(live, Rest, New_State, Reply);

handle_msg(Type, [{signed_integrity, _Data} | Rest], State, Reply) ->
    ?WARN("~p leecher: unexpected signed_integrity message ~n", [Type]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% REQUEST
handle_msg(Type, [{request,_Payload} | Rest], State, Reply) ->
    ?WARN("~p leecher: unexpected REQUEST message ~n", [Type]),
    handle_msg({Type, leecher}, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% CANCEL
%% TODO implement this
handle_msg(Type, [{cancel, _Data} | Rest], State, Reply) ->
    ?WARN("~p leecher: unexpected CANCEL message ~n", [Type]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% CHOKE
handle_msg(Type, [{choke, _Data} | Rest], State, Reply) ->
    ?WARN("~p leecher: unexpected choke message ~n", [Type]),
    handle_msg(Type, Rest, State, Reply);

%%-----------------------------------------------------------------------------
%% UNCHOKE
%% TODO implement this
handle_msg(Type, [{unchoke, _Data} | Rest], State, Reply) ->
    ?WARN("~p leecher: unexpected choke message ~n", [Type]),
    handle_msg(Type, Rest, State, Reply);

%% currently no implementation
handle_msg({Type, Role}, [{pex_resv6, _Data} | Rest], State, Reply) ->
    ?WARN("live_seeder: unexpected pex_resv6 message ~n", []),
    handle_msg({Type, Role}, Rest, State, Reply);
handle_msg({Type, Role}, [{pex_rescert, _Data} | Rest], State, Reply) ->
    ?WARN("live_seeder: unexpected pex_rescert message ~n", []),
    handle_msg({Type, Role}, Rest, State, Reply).
