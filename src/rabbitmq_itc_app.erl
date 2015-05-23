-module(rabbitmq_itc_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _StartArgs) ->
	rabbitmq_itc:start_link([]).

stop(_State) ->  
	ok.
  
