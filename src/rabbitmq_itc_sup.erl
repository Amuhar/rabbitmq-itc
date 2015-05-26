-module(rabbitmq_itc_sup).

-behaviour(supervisor).

-include_lib("rabbit_common/include/rabbit.hrl").

-compile([export_all]).

%%----------------------------------------------------------------------------

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Args) ->
    supervisor:start_child(
      ?MODULE,
      {itc, {rabbitmq_itc, start_link, [Args]},
       transient, ?MAX_WAIT, worker,
       [rabbitmq_itc]}).

stop_child(Id) ->
    supervisor:terminate_child(?SUPERVISOR, Id),
    supervisor:delete_child(?SUPERVISOR, Id),
    ok.


init([]) -> {ok, {{one_for_one, 3, 10},[]}}.