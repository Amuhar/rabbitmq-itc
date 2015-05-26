-module(rabbit_itc_wm_chain).

-compile([export_all]).

-include_lib("rabbitmq_management/include/rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").

%%--------------------------------------------------------------------

init(_Config) -> {ok, #context{}}.

content_types_provided(ReqData, Context) ->
   {[{"application/json", to_json}], ReqData, Context}.

content_types_accepted(ReqData, Context) ->
   {[{"application/json", accept_content}], ReqData, Context}.  

to_json(RD, Context) ->
    {F,T,File} = ids(RD),
    Ids = {F,T},
    case Ids of
      {From,To} ->
        Reply = rabbitmq_itc:chain({From,To}),
        rabbit_mgmt_util:reply(Reply, RD, Context);
              _ ->
        rabbit_mgmt_util:reply([none], RD, Context) %% должна отправлять цепочку событий 
    end.

allowed_methods(ReqData, Context) ->
    {['HEAD', 'GET', 'PUT'], ReqData, Context}.

accept_content(RD, Ctx) ->
V = vhost(RD),
if 
    V == none orelse V == "undefined" ->
             {From,To,File} = ids(RD),
              Reply = rabbitmq_itc:chain({From,To}),
              {ok,Io} = file:open(File,[append]),
              A = lists:flatten(io_lib:format("~p", [Reply])),
              Data = io_lib:format("~s~n",[A]),
              file:write(Io,Data),
              file:close(Io),
              {true, RD, Ctx};
    true ->
          rabbitmq_itc_sup:start_child(V),
          {true, RD, Ctx}
end.

is_authorized(ReqData, Context) ->
    rabbit_mgmt_util:is_authorized_admin(ReqData, Context).

%%--------------------------------------------------------------------------
ids(RD) ->
  PathInfo =wrq:path_info(RD),
  case [orddict:find(from,PathInfo),orddict:find(to,PathInfo),orddict:find(file,PathInfo)] of
      [{ok,From},{ok,To},{ok,File}] -> 
                         {F,[]} = string:to_integer(From),
                         {T,[]} = string:to_integer(To),
                         {F,T,File ++ ".txt"};
      _ -> none
  end.

vhost(RD) ->
  PathInfo =wrq:path_info(RD),
  case [orddict:find(vhost,PathInfo)] of
      [{ok,Vhost}] -> 
                         Vhost;
                 _ ->    none
  end.


