-module(rabbit_itc_wm_bd).

-compile([export_all]).

-include_lib("rabbitmq_management/include/rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").

%%--------------------------------------------------------------------

init(_Config) -> {ok, #context{}}.

allowed_methods(ReqData, Context) ->
    {['HEAD', 'GET'], ReqData, Context}.

content_types_provided(ReqData, Context) ->
   {[{"application/json", to_json}], ReqData, Context}. %% for get


to_json(ReqData, Context) ->
    rabbit_mgmt_util:reply(rabbitmq_itc:all(), ReqData, Context).

is_authorized(ReqData, Context) ->
    rabbit_mgmt_util:is_authorized_admin(ReqData, Context).



%%--------------------------------------------------------------------


