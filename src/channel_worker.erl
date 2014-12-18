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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc channel worker
%% <p>manages a single peer endpoint, for a given swarm.</p>
%% @end

-module(channel_worker).
-include("swirl.hrl").
-behaviour(gen_server).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-spec test() -> term().
-endif.

%% api
-export([start_link/2,
         stop/1]).

%% gen_server
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% records and state

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% api

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc start the channel using provided peer info (typically the udp endpoint)
%% for channel 0, i.e. the initial handshake contact from a remote peer, we
%% effectively block any re-registration by registering this name, until the
%% first received registration completes successfully.
-spec start_link(ppspp_datagram:endpoint(), ppspp_options:swarm_id()) ->
    ignore | {error,_} | {ok,pid()}.
start_link(Peer, Swarm_id)  ->
    Uri = ppspp_datagram:get_peer_uri(Peer),
    Registration = {via, gproc, {n, l, {?MODULE, Uri}}},
    gen_server:start_link(Registration, ?MODULE, [Peer, Swarm_id], []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Stops the server.

-spec stop(ppspp_channel:channel()) -> ok | {error, any()}.
stop(Channel) ->
    case where_is(Channel) of
        {error, Reason} -> {error, Reason};
        {ok, Pid} -> gen_server:cast(Pid, stop)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Looks up the pid for a given channel.

-spec where_is(ppspp_channel:channel()) -> {ok, pid()} | {error,_}.
where_is(Channel)  ->
    case Pid = gproc:lookup_local_name({?MODULE, Channel}) of
        undefined -> {error, ppspp_channel_worker_not_found};
        _ -> {ok, Pid}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% callbacks

%% @doc as the channel id is not known at time of process spawning, it is
%% done during init phase, using gproc. The following values are registered:
%% - {{peer, Peer URI}, Peer}
%% - {{channel, Channel id}, Swarm ID}
%% Peer is the opaque data type used in the datagram module that uniquely
%% identifies a remote peer.
%% TODO change registration of peers to allow multiplexed peers per remote
%% address, and therefore multiple swarms on the same IP.
%% TODO enable updating the registration of the URI to match the acquired
%% channel that will accommodate all future datagrams from this peer.

-spec init(ppsp_options:swarm()) ->
    {ok, ppspp_channel:channel()}.
init(Swarm_id) ->
    {ok, ppspp_channel:acquire(Swarm_id)}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
