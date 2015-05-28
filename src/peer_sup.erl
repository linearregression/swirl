%% -*- tab-width: 4;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ft=erlang ts=4 sw=4 et
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

-module(peer_sup).
-include("swirl.hrl").

-behaviour(supervisor).

%% api
-export([start_link/0,
         start_child/1 ]).

%% callbacks
-export([init/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% api

-spec start_link() -> {ok, pid()} | ignore | {error, any()}.

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%-spec start_child(port()) -> ok.
-spec start_child([inet:port_number()]) ->
    {error,_} | {ok, pid()}.
start_child([Port]) when is_integer(Port) ->
    supervisor:start_child(?MODULE, [Port]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% callbacks

-spec init([]) -> {ok,{{simple_one_for_one, 10,60}, [supervisor:child_spec()] }}.
init([])->
    RestartStrategy = simple_one_for_one,
    MaxRestarts = 10,
    MaxSecondsBetweenRestarts = 60,
    Options = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    Restart = transient,
    Shutdown = 1000,
    Type = worker,

    Worker = {peer_worker, {peer_worker, start_link, []},
              Restart,
              Shutdown,
              Type,
              [peer_worker]},

    {ok, {Options, [Worker]}}.
