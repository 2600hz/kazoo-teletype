%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2021-2024, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(teletype_conference_email_invite).

-export([init/0
        ,handle_req/1
        ]).

-include("teletype.hrl").

-define(TEMPLATE_ID, <<"conference_email_invite">>).

-define(TEMPLATE_MACROS
       ,kz_json:from_list(
          [?MACRO_VALUE(<<"invite.conference_id">>, <<"conference_id">>, <<"Conference ID">>, <<"Conference ID">>)
          ,?MACRO_VALUE(<<"invite.conference_numbers">>, <<"conference_numbers">>, <<"Conference Numbers">>, <<"Conference Numbers">>)
          ,?MACRO_VALUE(<<"invite.conference_name">>, <<"conference_name">>, <<"Conference Name">>, <<"Conference Name">>)
          ,?MACRO_VALUE(<<"invite.conference_link">>, <<"conference_link">>, <<"Conference Link">>, <<"Conference Link">>)
          ,?MACRO_VALUE(<<"invite.conference_call_in_numbers">>, <<"conference_call_in_numbers">>, <<"Conference Call-In Numbers">>, <<"Conference Call-In Numbers">>)
          ,?MACRO_VALUE(<<"invite.conference_participant_pins">>, <<"conference_participant_pins">>, <<"Conference Participant Pins">>, <<"Conference Participant Pins">>)
          ,?MACRO_VALUE(<<"invite.invite_message">>, <<"invite_message">>, <<"Invite Message">>, <<"Invite Message">>)
          | ?COMMON_TEMPLATE_MACROS
          ]
         )
       ).

-define(TEMPLATE_SUBJECT, <<"You have been invited to a conference">>).
-define(TEMPLATE_CATEGORY, <<"conference">>).
-define(TEMPLATE_NAME, <<"Email Invite">>).

-define(TEMPLATE_TO, ?CONFIGURED_EMAILS(?EMAIL_ORIGINAL)).
-define(TEMPLATE_FROM, teletype_util:default_from_address()).
-define(TEMPLATE_CC, ?CONFIGURED_EMAILS(?EMAIL_SPECIFIED, [])).
-define(TEMPLATE_BCC, ?CONFIGURED_EMAILS(?EMAIL_SPECIFIED, [])).
-define(TEMPLATE_REPLY_TO, teletype_util:default_reply_to()).

-spec init() -> 'ok'.
init() ->
    kz_log:put_callid(?MODULE),
    teletype_templates:init(?TEMPLATE_ID, [{'macros', ?TEMPLATE_MACROS}
                                          ,{'subject', ?TEMPLATE_SUBJECT}
                                          ,{'category', ?TEMPLATE_CATEGORY}
                                          ,{'friendly_name', ?TEMPLATE_NAME}
                                          ,{'to', ?TEMPLATE_TO}
                                          ,{'from', ?TEMPLATE_FROM}
                                          ,{'cc', ?TEMPLATE_CC}
                                          ,{'bcc', ?TEMPLATE_BCC}
                                          ,{'reply_to', ?TEMPLATE_REPLY_TO}
                                          ]),
    teletype_bindings:bind(<<"email_invite">>, ?MODULE, 'handle_req').

-spec handle_req(kz_json:object()) -> template_response().
handle_req(JObj) ->
    handle_req(JObj, kapi_notifications:email_invite_v(JObj)).

-spec handle_req(kz_json:object(), boolean()) -> template_response().
handle_req(_, 'false') ->
    lager:debug("invalid data for ~s", [?TEMPLATE_ID]),
    teletype_util:notification_failed(?TEMPLATE_ID, <<"validation_failed">>);
handle_req(JObj, 'true') ->
    lager:debug("valid data for ~s, processing...", [?TEMPLATE_ID]),

    %% Gather data for template
    DataJObj = kz_json:normalize(JObj),
    process_req(DataJObj).

-spec build_macro_data(kz_json:object()) -> kz_term:proplist().
build_macro_data(DataJObj) ->
    DataInviteToList = kz_json:to_proplist(kz_api:remove_defaults(DataJObj)),
    ConferenceNumbers = props:get_value(<<"conference_numbers">>, DataInviteToList),
    ConferenceNumbersFormatted = kz_binary:join(ConferenceNumbers,<<", ">>),
    ConferenceCallInNumbers = props:get_value(<<"conference_call_in_numbers">>, DataInviteToList),

    Response= [{<<"system">>, teletype_util:system_params()}
              ,{<<"account">>, teletype_util:account_params(DataJObj)}
              ,{<<"invite">>, props:delete(<<"guests">>, DataInviteToList)}
              ],
    props:set_values([{[<<"invite">>,<<"conference_numbers_formatted">>], ConferenceNumbersFormatted}
                     ,{[<<"invite">>,<<"conference_call_in_numbers">>], lists:delete(<<"undefinedconf">>, ConferenceCallInNumbers)}
                     ], Response).

-spec process_req(kz_json:object()) -> template_response().
process_req(DataJObj) ->
    Macros = build_macro_data(DataJObj),

    %% Populate templates
    RenderedTemplates = teletype_templates:render(?TEMPLATE_ID, Macros, DataJObj),

    AccountId = kapi_notifications:account_id(DataJObj),
    {'ok', TemplateMetaJObj} =
        teletype_templates:fetch_notification(?TEMPLATE_ID
                                             ,AccountId
                                             ),

    Subject = teletype_util:render_subject(kz_json:find(<<"subject">>, [DataJObj, TemplateMetaJObj], ?TEMPLATE_SUBJECT)
                                          ,Macros
                                          ),

    Emails0 = teletype_util:find_addresses(DataJObj, TemplateMetaJObj, ?TEMPLATE_ID),
    Emails = props:set_value(<<"to">>, get_email_address(DataJObj, Emails0, teletype_util:is_preview(DataJObj)), Emails0),
    TemplateAccountId = teletype_util:get_template_account_id(TemplateMetaJObj, AccountId),

    case teletype_util:send_email(Emails, Subject, RenderedTemplates, TemplateAccountId) of
        'ok' -> teletype_util:notification_completed(?TEMPLATE_ID);
        {'error', Reason} -> teletype_util:notification_failed(?TEMPLATE_ID, Reason)
    end.

-spec get_email_address(kz_json:object(), kz_term:proplist(), boolean()) -> kz_term:api_ne_binaries().
get_email_address(_DataJObj, Emails0, 'true') ->
    props:get_value(<<"to">>, Emails0);
get_email_address(DataJObj, Emails0, 'false') ->
    ToEmails = props:get_value(<<"to">>, Emails0),
    case kz_json:get_value(<<"guests">>, DataJObj) of
        <<"Email">> ->
            [];
        [] ->
            ToEmails;
        Emails when is_list(Emails) ->
            case [E || E <- Emails, kz_term:is_ne_binary(E)] of
                [] -> ToEmails;
                Es -> Es
            end;
        _Other ->
            ToEmails
    end.

