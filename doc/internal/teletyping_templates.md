# Teletype Template Guide

Teletype is an application that receives some AMQP messages finds its
corresponding email template Erlang module, render its email templates, and send
it to recipient email addresses.

The mechanics for each notification email sent from Teletype:

1. Template Erlang module and its HTML / Plain Text files: Teletype will auto
   load and init the configured teletype modules on startup
2. Notification publisher: Each Kazoo app at some point will fire the AMQP
   message to teletype, mostly via `kapps_notify_publisher` Kazoo Core module
   and use one of defined `kapi_notifications` as publisher function
3. Notification receiver: Teletype will listen for these, and based on the event
   name will call appropriate teletype template module for processing the
   notification, render and sending emails

## Publisher side of notification

Kazoo apps will publish the notification request AMQP message via a helper call
`kapps_notice_publisher` in Kazoo core. This publisher will handle situation if
the teletype fails to receive or process the notification request in time, saves
its payload to database to attempt retries later by `notify_resend_maintenance`
in the Tasks app.

- `kapps_notice_publisher:call_collect/2`: will call and waits for a success or
  failed response from Teletype. If not received a response in time from
  teletype will save payload and returns an error back to the caller
- `kapps_notice_publisher:cast/2`: will fire the event in a new spawned process
  and return immediately to the caller, the new spawn acts exactly like
  `call_collect/2`

## Receiver side of notifications

Multiple app may listen for `notifications` AMQP messages (`teletype`,
`webhooks`, and `blackhole`). AMong those only Teletype will send response back
to publisher. Remember to always respond back in your template module otherwise
auto re-attempt mechanism of publisher and notify resend will kick in and the
user may receive multiple emails.

In case of multiple emails, there may be a fault in notify resend or the publisher
may not received the success response in time from teletype.

## Add templates in other applications

Traditionally Teletype provided a place to define and include all notification
used by any Kazoo parts.

Nowadays more applications which may not be part of Kazoo and are not part of
regular kazoo release require to include Teletype templates. All these apps
eventually needed to define their `KApi` definitions, publisher and etc in
`kapi_notifications` Kazoo core module.

To ease extending of any `KApi` core module, a plumping is added to
`kapi_definition` module, so applications can now add binding for
`api_definitions` to return a list of all their `api_definition` and
`api_defition/1` to retrieve a single one.

You may now completely define your Teletype templates (Erlang module and its
attachments) inside your application and use this new plumping to wire your
notification into `kapi_notifications`.

First you need to write your template Erlang module, have the standard
`api_definiton/0` and its message builder, validator, and publisher function as
usual.

Then in your application startup you bind it (here the template name is
`my_awesome_template`):

```erlang
-define(INTEGRATION_MODULES, [{'teletype_my_awesome_template', 'teletype_maintenance', 'start_module'}
                             ]
       ).

start() ->
    %% ...
    kz_module:application_integrations(?INTEGRATION_MODULES),
    kapi_definition:bind_api_definitions(<<"notifications">>, ?MODULE, 'api_definitions'),
    kapi_definition:bind_api_definition(<<"notifications">>, ?MODULE, 'api_definition'),
    %% ...

stop() ->
    %% ...
    kapi_definition:unbind_api_definitions(<<"notifications">>, ?MODULE, 'api_definitions'),
    kapi_definition:unbind_api_definition(<<"notifications">>, ?MODULE, 'api_definition'),
    _ = teletype_bindings:flush_mod('teletype_my_awesome_template'),
    %%...


-spec api_definitions() -> kapi_definition:apis().
api_definitions() ->
    [teletype_my_awesome_template:api_definition()].

-spec api_definition(kz_term:ne_binary()) -> kapi_definition:api().
api_definition(<<"my_awesome_template">>) ->
    teletype_my_awesome_template:api_definition();
api_definition(_) ->
    'undefined'.
```

And just define regular `api_definition` in your template module as you define it `kapi_notificaions`:

```erlang
-module(teletype_my_awesome_template).

-spec api_definition() -> kapi_definition:api().
api_definition() ->
    Setters = [{fun kapi_definition:set_build_fun/2, fun build_notification/1}
              ,{fun kapi_definition:set_validate_fun/2, fun notification_v/1}
              ,{fun kapi_definition:set_publish_fun/2, fun publish_notification/1}
              %% ...
              %% ...
              ],
    kapi_definition:setters(Setters).

build_notification(Prop) ->
   %% ...

notificaion_v(Prop) ->
   %% ...

publish_notificaion(Prop) ->
   %% ...

publish_notification(API, ContentType) ->
   %% ...
```

When initializing your template you MUST pass `html` and `text` prop list or
define their callbacks with value of `{AppAtomName, TemplateId}` so
`teletype_templates` can find the HTML and Text attachments from your
applications `priv/templates` folder instead of Teletype application.

And lastly and obviously 

## Teletype template Erlang module

Teletype will call `Modole:init/0` function on startup of each module. This only
updates the notification metadata in system config, if they have changed. If the
db document hash is different, this will not do update the doc. If you edit the
metadata if an existing templates you may want to use do the same during dev
time to update the metadata in system config.

To actually update the HTML and Text template files you have to call
`teletype_maintenance:restore_system_template({TEMPLATE_NAME})`.

See [Teletype maintenance](../maintenance.md) documentation for more info.

Teletype will use event name as uses bind modules for that event to process and
send the email.

Currently we have two variant. We general expect newer template modules use the
newer variant.

The Erlang module is expected to:

- Initialize the template metadata (almost most of time in system config)
- Adding teletype binding for its notification for processing
- Handle and process request for its notifications

In handling part it is usually expected:

1. Validate the AMQP payload, it is expected the module also maintain a
   normalized of the request JObj.
2. Check if the notification is enabled or not in the account
3. Gather data and create the require macros for rendering the template
4. Render the template
5. Find email address
6. Send the email
7. Notify the publisher of any success, disable, ignored, failures, and if the
   process takes a long time occasionally send update back to the publisher

#### Older modules

Older template module format was just expecting to have at least two functions
exported:

- `init/0`: Will init the template metadata to be saved into system config
  database and add teletype binding for the notification name, this will only
  called during startup
- `handle_req/1`: Or another function specified in teletype binding in `init/0`
  function, which will be called for each received notification AMQP message

`init/0` function is expected to use `teletype_templates:init/2`, which accepts
all template's metadata as a prop-list for initialization.

Given `missed_call` as Template ID (name):

```erlang
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
teletype_bindings:bind(<<"missed_call">>, ?MODULE, 'handle_req').
```

#### New modules using `teletype_gen_email_template` behavior

The main difference that this variant must use `teletype_templates:init/1` to
initialize the template's metadata. All metadata are expected to defined as
exported functions.

Please use the new format for new modules. We may update old modules to use the
new format in the future.

```erlang
-export([init/0, handle_req/1]).
-export([id/0
        ,macros/0
        ,subject/0
        ,category/0
        ,friendly_name/0
        ,to/0, from/0, cc/0, bcc/0, reply_to/0
        %% optional callbacks:
        %% ,macros/1 %% used only by testing modules
        %% ,account_id/0
        %% ,html/0
        %% ,text/0
        ]).
```

### Template Metadata

| Name            | Required | Description                                                                                                                                                                                     |
| --------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `macros`        | `true`   | A prop list of macros used in template as information to UI when users customizing their templates. A JSON object, you may use `MACRO_VALUE` macro                                              |
| `subject`       | `true`   | The subject of the email, can be a template                                                                                                                                                     |
| `category`      | `true`   | The category of the notification, used in UI to grouped related notifications                                                                                                                   |
| `friendly_name` | `true`   | A friend name used in UI app                                                                                                                                                                    |
| `to`            | `true`   | The email address config used for `to`, see below for config description                                                                                                                        |
| `from`          | `true`   | The email address used for `from`, a string. Use the value from `teletype_util:default_from_address()`                                                                                          |
| `cc`            | `true`   | The email address config used in `cc`, see below for config description                                                                                                                         |
| `bbc`           | `true`   | The email address config used in `bcc`, see below for config description                                                                                                                        |
| `reply_to`      | `true`   | The email address used for `from`, a string. Use the value from `teletype_util:default_from_address()`                                                                                          |
| `account_id`    | `false`  | Only use when you want instruct Teletype to save the template doc to specific account DB instead of system config, usually reduce the visibility of the template to that specific account       |
| `html`          | `false`  | If the template is in app other than teletype you may use `{AppAtomName, TemplateId}` as value so `teletype_templates` knows where to read the template's HTML attachment from filesystem       |
| `text`          | `false`  | If the template is in app other than teletype you may use `{AppAtomName, TemplateId}` as value so `teletype_templates` knows where to read the template's plain text attachment from filesystem |

When defining the `macros`, it usually expected the module at least includes the
`system` macros, using `SYSTEM_MACROS` macro. During handling the request, use
`teletype_util:system_params()`.

For other common macros look at `teletype/include/teletype_template.hrl`.

If your module is defined in an app other than Teletype, you MUST use
`{AppName, TemplateId}` for both `html` and `text` metadata. Otherwise the init
will fail. See [Add templates in other applications](#add-templates-in-other-applications).

For Email config you may use `CONFIGURED_EMAILS` macro which encapsulates it as
JSON as follow:

| Name              | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `type`            | One of he type: <br /><ul><li>`"original"` (`EMAIL_ORIGINAL` macro): Look for email address inside the request data, if not found use template metadata</li><li>`"specified"` (`EMAIL_SPECIFIED` macro): Look for email addresses in template metadata, if not found use request data</li><li>`"admins"` (`EMAIL_ADMINS` macro): Send to all admin users of the reseller of the request's account id, if account id is itself a reseller, send to all its admins</li></ul> |
| `email_addresses` | A list of email addresses as string                                                                                                                                                                                                                                                                                                                                                                                                                                        |

For type `original`, or `specified`, it is expected the template module to find
the appropriate email addresses before calling `teletype_util:find_addresses/3`.

If the request has `Preview` header, it is expected that request already has
`to` email set to the previewer email address. UI usually for sending a preview
notification, will set the `to` email type to `specific` and `email_addresses`
to the requested email address.

### Notice enabled, send respond back to publisher

Always check if the notice enabled for the account or not using
`teletype_util:is_notice_enabled/3`.

Always send a respond back to publisher, so it won't be timeout and tries to
resend the email.

- `teletype_util:notification_completed/1`: If the email is sent successfully
- `teletype_util:notification_ignored/1`: If for any reason the request is not
  being process for sending email, and you may simply want to ignore the
  notification without failing and causing publisher to attempt to resend the
  same request again, use this.
- `teletype_util:notification_disabled/2`: If the notice is disable on the
  account
- `teletype_util:notification_failed/2`: If there is an error during sending the
  mail

### Macros and gather data

Main job of template module is to gather the needed data from the request for
rendering the templates.

Depends on the value there are some utility in `teletype_util` you may use.

- `system_params/0`: gathers macros used in `system` macro
- `account_params/1`: gathers macros used in `account` macro
- `user_params/1`: gathers macros from a User JObj to use in user related macros
- `branding_params/1`: gathers branding macros if templates need those macros or
  call `find_branding_params/1` for account ID
- `open_doc/3`: utility for open a doc type safely
- `timestamp_params/3`: builds time related macros of current time to be used in
  template
- `fix_timestamp/1`, `fix_timestamp/2`, `fix_timestamp/3`: use these to properly
  update any Gregorian timestamp according to the configured timezone of the
  account
- `build_call_data/2`: pass `kapps_call` JSON object and this builds appropriate
  macros to be used in template
- `public_proplist/2`: to avoid passing private fields to templates during
  render, call this on appropriate keys in the data object
- `maybe_get_attachments/1` and `fetch_attachment_from_url/1` if you template
  needs to open and include an attachment (like voicemail media file)
  get_template_account_id/2

## HTML and Plain Text template files

Teletype templates provides email template body for both an HTML based email and plain text based.

### Template language

We use ErlyDTL as template language for plain text, HTML, and the subject of the
email.

To render pass a long the template and the macros from your module and ErlyDTL
will generate the final rendered email.

Using a template, we can parameterize some content of the notification. ErlyDTL
is Erlang implementation of Python Django Template language. More specifically
[version `1.6.x`](https://django.readthedocs.io/en/1.6.x/ref/templates/builtins.html)
of it. We recommend to familiar yourself with Django template prior to
writing/editing template files.

### Some highlights

- Check for spelling and grammar
- Be nice, courteous and provide descriptive and useful info to the user
- Stick to current styling for both plain text and HTML as much as possible
- For HTML be aware that the user may open this email in janky email client
  which will definitely will not have a good HTML rendering support (_cough_
  _cough_ _Outlook_)
  - See HTML part below
- Always format the timestamp using `date` tag (also remember to fix timestamp
  on your macros values to adjust its timezone)
- DO not leak sensitive info (node name/host name and etc...)
- Usually we want to include account information, unless the email may be sent
  to unknown user (password reset for example) which in that case we don't want
  to expose sensitive info like account info
- Be aware of spacing if you using conditional, loop tags
- If possible include `Sent from {{system.encoded_node}}` at the end of your
  email
- In HTML be aware that you may want to escape special characters

### Plain text

Plain text email is straightforward, we highly recommend you stick to the
current formatting of the other teletype template. Just remember pay extra
attention to spaces if you are using conditions in your template, to not include
extra spaces if your want to output a variable only if is defined.

**DO NOT**: `Hello {% if name %}{{name}}{% endif %}:`, will render `Hello :` if
`name` is not defined

**DO**: `Hello{% if name %}{{name}}{% endif %}:`, will render correctly to
`Hello:` if `name` is not defined

### HTML

Remember [Browser wars](https://en.wikipedia.org/wiki/Browser_wars)? Well
surprise we are not done yet, well at least in the domain of rendering emails in
different email clients.

Different email clients will use different HTML rendering version, in their
different version, and on different platforms (Web, Windows, macOS, Linux, and
mobile apps).

Existing teletype template tried their best to be compatible with all clients as
much as possible. But it is inevitable and issues are still exists.

For example try forward a teletype email from outlook on web and open it in a
windows machine outlook app :)

Also the way Monster UI Branding app is saving the customization is not helping,
since it removes the important bits from `head` and only include the content of
`<body>` tag.

For this reason, we highly recommend to set the important font, color, and maybe
even sizing, padding styles directly on each `<p>`, `<a>`, `<td>` and etc... to
avoid these issue as much as possible.

We also highly recommend to start using HTML email frameworks like
[MJML](https://mjml.io) to mitigate rendering issues in email client as much as
possible.

- Read [their documentation](https://documentation.mjml.io/)
- You may use [Try it live](https://mjml.io/try-it-live) or run their desktop
  app, using Try it live or desktop has benefit of editing MJML and seeing the
  result in real-time.

You can use existing Teletype template that already using MJML as starting point
and work you way towards your own template.

After your design is done, copy, and save both MJML and its HTML output and save
them. In future next person can use MJML and update the HTML again if needed.

## Testing Email in your dev environment

During dev time, you may want to test out the HTML and plain text to make sure
the look and render alright.

You may want too look into mock or test SMTP server with ability to of providing
SMTP server to catch any email and have show them in their UI.

There are a few but our favorites are [MailCatcher](https://mailcatcher.me/) and
[Mailpit](https://mailpit.axllent.org).

Here for example you may start an instance of MailCatcher using Docker, then you
can configure teletype `smtp_client` to point to it. Then use its interface to
see the receive emails.

```shell
docker run -d -it --net host --rm schickling/mailcatcherdocker
```

This will starts SMTP server on all interface at port `1025`, and its UI at port
`1080`.
