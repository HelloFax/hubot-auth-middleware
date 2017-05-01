# Description:
#   Auth-middleware adds listener-middleware for command access controls
#
#   Auth-middleware adds listener-middleware that checks listener.options for
#   command access control defined by: 
#     - hubot-auth roles
#     - rooms
#     - hubot-auth-middleware environments
#
#   Setting the HUBOT_AUTH_MIDDLEWARE_IGNORE_NO_AUTH environment variable to
#   true makes hubot skip listener-middleware checks for any listener without a
#   listener.options.auth = true. This is useful for multi-bot scenarios where
#   external scripts are in use. Alternatively, setting the
#   HUBOT_AUTH_MIDDLEWARE_QUARANTINE_NO_AUTH environment variable to a room
#   will only respond to non-auth configured listeners in a particular room.
#   ...IGNORE_NO_AUTH must be false for room quarantining of no-auth listeners
#   to function.
#
#   Listener options should use the following format:
#     { "id":"someId",
#       "auth":"true",
#       "rooms":["roomId1","roomId2"],
#       "roles":["roleName1", "roleName2"],
#       "env":"authMiddlewareEnv"
#     }
#  
#   If there are no restrictions of a particular type, simply omit the
#   attribute. To limit a command only to a particular room and add no 
#   other limations:
#     { "id":"someId",
#       "room":"powerUserRoomId"
#     }
#
# Dependencies:
#   hubot-auth
#
# Configuration:
#   HUBOT_AUTH_MIDDLEWARE_ENVIRONMENT - defaults to "production"
#   HUBOT_AUTH_MIDDLEWARE_ENVIRONMENT_REPLY - defaults to false
#   HUBOT_AUTH_MIDDLEWARE_IGNORE_NO_AUTH - defaults to false
#   HUBOT_AUTH_MIDDLEWARE_QUARANTINE_NO_AUTH - no default, undefined is disabled.
#
# Commands:
#
logPrefix         = 'auth-middleware'
successAction     = 'Accepting (valid auth)'
ignoreNoAuth      = process.env.HUBOT_AUTH_MIDDLEWARE_IGNORE_NO_AUTH or false
authMiddlewareEnv = process.env.HUBOT_AUTH_MIDDLEWARE_ENVIRONMENT or 'production'
environmentReply  = process.env.HUBOT_AUTH_MIDDLEWARE_ENVIRONMENT_REPLY or false
quarantineNoAuth  = process.env.HUBOT_AUTH_MIDDLEWARE_QUARANTINE_NO_AUTH 

authFail = (context, errorMsg) ->
  context.response.reply errorMsg
  context.response.message.finish()

module.exports = (robot) ->

  robot.listenerMiddleware (context, next, done) ->
    opts    = context.listener.options
    reqUser = robot.brain.userForName(context.response.message.user.name)
    reqRoom = context.response.message.room
    reqMsg  = context.response.message.text
    action  = successAction

    # Default to arrays so listeners can pass a single string
    opts.roles = [opts.roles] if typeof opts.roles is 'string'
    opts.rooms = [opts.rooms] if typeof opts.rooms is 'string'

    if opts.auth is "true" 
      if opts.env not in [ undefined, authMiddlewareEnv ]
        action = 'Rejecting (env)'
        # By default, don't respond in this case. Env quarantining supports multiple hubots,
        # we want the instance to skip the task, but not clutter the chat room. Env var override available.
        if environmentReply
          authFail context, "#{action} '#{reqUser.name}: #{reqMsg}' -- not executing from this env (hubot instance: #{opts.env})"
        else
          context.response.message.finish()
      if opts.rooms != undefined 
        if reqRoom not in opts.rooms
          action = 'Rejecting (room)'
          authFail context, "#{action} '#{reqUser.name}: #{reqMsg}' -- use this room: #{reqRoom}"
      if opts.roles != undefined
        if robot.auth.hasRole(reqUser, opts.roles) is false
          action = 'Rejecting (role)'
          authFail context, "#{action} '#{reqUser.name}: #{reqMsg}' -- only allowed by users in role(s): #{opts.roles}"

      # TODO - add a confirmation require w/ timeout? 
      # Spit out a code and the users in a role, and if someone responds with
      # the code write a flag to redis. Periodically check the flag in the timout?

      robot.logger.info "#{logPrefix}: #{action} '#{reqMsg}' request from user: #{reqUser.name} (#{reqUser.id}), room: #{reqRoom}, env: #{authMiddlewareEnv}"

      if action == successAction
        next()
      else
        done()

    else if ignoreNoAuth is "true"
      # Ignore any requests with no listener.options.auth setting
      action = 'Rejecting (ignore_no_auth)'
      context.response.message.finish()

      robot.logger.info "#{logPrefix}: #{action} '#{reqMsg}' request from user: #{reqUser.name} (#{reqUser.id}), room: #{reqRoom}, env: #{authMiddlewareEnv}"
      done()

    else if quarantineNoAuth
      if quarantineNoAuth != reqRoom
        # Ignore any requests with no listener.options.auth setting from outside the quarantine room
        action = 'Rejecting (quarantine_no_auth)'
        context.response.message.finish()

        robot.logger.info "#{logPrefix}: #{action} '#{reqMsg}' request from user: #{reqUser.name} (#{reqUser.id}), room: #{reqRoom}, env: #{authMiddlewareEnv}"
        done()
      else
        # Auth isn't configured, quarantine is AND we are in the quarantine room: proceed
        action = 'Accepting (in quarantine)'

        robot.logger.info "#{logPrefix}: #{action} '#{reqMsg}' request from user: #{reqUser.name} (#{reqUser.id}), room: #{reqRoom}, env: #{authMiddlewareEnv}"
        next()

    else
      # Auth isn't configured, and either the ignore no auth flag isn't set
      action = 'Accepting (without auth checks)'

      robot.logger.info "#{logPrefix}: #{action} '#{reqMsg}' request from user: #{reqUser.name} (#{reqUser.id}), room: #{reqRoom}, env: #{authMiddlewareEnv}"
      next()

