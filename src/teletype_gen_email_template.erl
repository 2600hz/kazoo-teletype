%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2025, 2600Hz
%%% @doc When implementing template modules, these callbacks are a must!
%%% @author Pierre Fenoll
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(teletype_gen_email_template).

-include_lib("teletype.hrl").

-optional_callbacks([account_id/0
                    ,html/0
                    ,text/0
                    ]).

%% must init module's templates and add binding
-callback init() -> ok.

%% template data
-callback category() -> kz_term:ne_binary().
-callback friendly_name() -> kz_term:ne_binary().
-callback id() -> kz_term:ne_binary().
-callback macros() -> kz_json:object().
-callback macros(kz_json:object()) -> kz_term:proplist().
-callback subject() -> kz_term:ne_binary().

%% email addresses to use for email
-callback to() -> kz_json:object().
-callback from() -> kz_term:api_ne_binary().
-callback cc() -> kz_json:object().
-callback bcc() -> kz_json:object().
-callback reply_to() -> kz_term:api_ne_binary().

%% allows app to override where and how to save the template and its attachments
%% defaults to read from teletype priv folder and save to KZ_CONFIG_DB
-callback account_id() -> kz_term:ne_binary().
-callback html() -> kz_term:ne_binary() | {atom(), kz_term:ne_binary()}.
-callback text() -> kz_term:ne_binary() | {atom(), kz_term:ne_binary()}.
