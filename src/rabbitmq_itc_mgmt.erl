
-module(rabbitmq_itc_mgmt).

-behaviour(rabbit_mgmt_extension).

-export([dispatcher/0, web_ui/0]).

dispatcher() -> [{["itc_bd"], rabbit_itc_wm_bd, []},
                 {["itc_bd",from,to,file], rabbit_itc_wm_chain, []}].

web_ui()     -> [{javascript, <<"bd.js">>}].