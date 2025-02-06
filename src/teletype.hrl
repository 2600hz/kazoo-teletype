-ifndef(TELETYPE_HRL).

-include_lib("kazoo_stdlib/include/kz_types.hrl").
-include_lib("kazoo_stdlib/include/kz_log.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-include("teletype_default_modules.hrl").

-define(APP, 'teletype').
-define(APP_NAME, (atom_to_binary(?APP, 'utf8'))).
-define(APP_VERSION, <<"4.0.0">>).

-define(PVT_TYPE, kz_notification:pvt_type()).

-define(CONFIG_CAT, <<"teletype">>).

-define(CACHE_NAME, 'teletype_cache').

-include_lib("teletype/include/teletype_template.hrl").

-define(AUTOLOAD_MODULES_KEY, <<"autoload_modules">>).
-define(AUTOLOAD_MODULES
       ,kapps_config:get(?CONFIG_CAT, ?AUTOLOAD_MODULES_KEY, ?DEFAULT_MODULES)
       ).

-define(TELETYPE_HRL, 'true').
-endif.
