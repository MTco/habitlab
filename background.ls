# console.log 'weblab running in background'

root = exports ? this

/*
execute_content_script = (tabid, options, callback) ->
  #chrome.tabs.query {active: true, lastFocusedWindow: true}, (tabs) ->
  if not tabid?
    if callback?
      callback()
    return
  chrome.tabs.executeScript tabid, {file: options.path, allFrames: options.all_frames, runAt: options.run_at}, ->
    if callback?
      callback()
*/

insert_css = (css_path, callback) ->
  # todo does not do anything currently
  if callback?
    callback()

export running_background_scripts = {}

load_background_script = (options, intervention_info, callback) ->
  if running_background_scripts[options.path]?
    # already running
    return callback?!
  background_script_text <- $.get options.path
  background_script_function = new Function('env', background_script_text)
  env = {
    intervention_info: intervention_info
  }
  background_script_function(env)
  running_background_scripts[options.path] = env
  callback?!

export wait_token_to_callback = {}

export make_wait_token = ->
  while true
    wait_token = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER)
    if not wait_token_to_callback[wait_token]
      return wait_token

export wait_for_token = (wait_token, callback) ->
  wait_token_to_callback[wait_token] = callback

export finished_waiting = (wait_token, data) ->
  callback = wait_token_to_callback[wait_token]
  delete wait_token_to_callback[wait_token]
  callback(data)

execute_content_scripts = (content_script_options, callback) ->
  console.log 'calling execute_content_scripts'
  tabs <- chrome.tabs.query {active: true, lastFocusedWindow: true}
  tabid = tabs[0].id
  # <- async.eachSeries intervention_info.content_script_options, (options, ncallback) ->
  #  execute_content_script tabid, options, ncallback

  wait_token = make_wait_token()

  wait_for_token wait_token, ->
    console.log 'wait token released'
    callback?!

  # based on the following
  # http://stackoverflow.com/questions/8859622/chrome-extension-how-to-detect-that-content-script-is-already-loaded-into-a-tab
  content_script_code = """
  (function(){
    chrome.runtime.sendMessage({
      type: 'load_content_scripts',
      data: {
        content_script_options: #{JSON.stringify(content_script_options)},
        tabid: #{tabid},
        wait_token: #{wait_token},
        loaded_scripts: window.loaded_scripts || {},
      },
    });
  })();
  """
  console.log content_script_code
  chrome.tabs.executeScript tabid, {code: content_script_code}
  #callback?! # technically incorrect, may be calling too early. TODO might break with multiple interventions
  /*
  'load_content_script': (data, callback) ->
    {options, tabid, loaded_scripts} = data
    if loaded_scripts[options.path]?
      return
    chrome.tabs.executeScript tabid, {file: options.path, allFrames: options.all_frames, runAt: options.run_at}, ->
      callback?!
  */
  #chrome.tabs.executeScript(tabid, {code: 'chrome.extension.sendRequest({type: "load_content_script", data: })'})
  #callback?!

load_intervention = (intervention_name, callback) ->
  console.log 'start load_intervention ' + intervention_name
  all_interventions <- get_interventions()
  intervention_info = all_interventions[intervention_name]

  console.log intervention_info
  console.log 'start load background scripts ' + intervention_name

  # load background scripts
  <- async.eachSeries intervention_info.background_script_options, (options, ncallback) ->
    load_background_script options, intervention_info, ncallback

  console.log 'start load content scripts ' + intervention_name

  # load content scripts
  <- execute_content_scripts intervention_info.content_script_options

  console.log 'done load_intervention ' + intervention_name
  callback?!

load_intervention_for_location = (location, callback) ->
  possible_interventions <- list_available_interventions_for_location(location)
  errors, results <- async.eachSeries possible_interventions, (intervention, ncallback) ->
    load_intervention intervention, ncallback
  callback?!

getLocation = (callback) ->
  #sendTab 'getLocation', {}, callback
  console.log 'calling getTabInfo'
  getTabInfo (tabinfo) ->
    console.log 'getTabInfo results'
    console.log tabinfo
    console.log tabinfo.url
    callback tabinfo.url

getTabInfo = (callback) ->
  chrome.tabs.query {active: true, lastFocusedWindow: true}, (tabs) ->
    console.log 'getTabInfo results'
    console.log tabs
    if tabs.length == 0
      return
    chrome.tabs.get tabs[0].id, callback

sendTab = (type, data, callback) ->
  chrome.tabs.query {active: true, lastFocusedWindow: true}, (tabs) ->
    console.log 'sendTab results'
    console.log tabs
    if tabs.length == 0
      return
    chrome.tabs.sendMessage tabs[0].id, {type, data}, {}, callback

export split_list_by_length = (list, len) ->
  output = []
  curlist = []
  for x in list
    curlist.push x
    if curlist.length == len
      output.push curlist
      curlist = []
  if curlist.length > 0
    output.push curlist
  return output

message_handlers = {
  'setvars': (data, callback) ->
    <- async.forEachOfSeries data, (v, k, ncallback) ->
      <- setvar k, v
      ncallback()
    callback()
  'getfield': (name, callback) ->
    getfield name, callback
  'getfields': (namelist, callback) ->
    getfields namelist, callback
  'getfields_uncached': (namelist, callback) ->
    getfields_uncached namelist, callback
  'requestfields': (info, callback) ->
    {fieldnames} = info
    getfields fieldnames, callback
  'requestfields_uncached': (info, callback) ->
    {fieldnames} = info
    getfields_uncached fieldnames, callback
  'getvar': (name, callback) ->
    getvar name, callback
  'getvars': (namelist, callback) ->
    output = {}
    <- async.eachSeries namelist, (name, ncallback) ->
      val <- getvar name
      output[name] = val
      ncallback()
    callback output
  'addtolist': (data, callback) ->
    {list, item} = data
    addtolist list, item, callback
  'getlist': (name, callback) ->
    getlist name, callback
  'getLocation': (data, callback) ->
    getLocation (location) ->
      console.log 'getLocation background page:'
      console.log location
      callback location
  'load_intervention': (data, callback) ->
    {intervention_name} = data
    load_intervention intervention_name, ->
      callback()
  'load_intervention_for_location': (data, callback) ->
    {location} = data
    load_intervention_for_location location, ->
      callback()
  'load_content_scripts': (data, callback) ->
    {content_script_options, tabid, wait_token, loaded_scripts} = data
    <- async.eachSeries content_script_options, (options, ncallback) ->
      if loaded_scripts[options.path]?
        return ncallback()
      chrome.tabs.executeScript tabid, {file: options.path, allFrames: options.all_frames, runAt: options.run_at}, ->
        return ncallback()
    new_loaded_scripts = {[k,v] for k,v of loaded_scripts}
    for options in content_script_options
      new_loaded_scripts[options.path] = true
    content_script_code = """
    (function() {
      window.loaded_scripts = #{JSON.stringify(new_loaded_scripts)}
    })();
    """
    <- chrome.tabs.executeScript tabid, {code: content_script_code}
    finished_waiting(wait_token)
}

ext_message_handlers = {
  'is_extension_installed': (info, callback) ->
    callback true
  # 'getfields': message_handers.getfields
  'requestfields': (info, callback) ->
    confirm_permissions info, (accepted) ->
      if not accepted
        return
      getfields info.fieldnames, (results) ->
        console.log 'getfields result:'
        console.log results
        callback results
  'requestfields_uncached': (info, callback) ->
    confirm_permissions info, (accepted) ->
      if not accepted
        return
      getfields_uncached info.fieldnames, (results) ->
        console.log 'getfields result:'
        console.log results
        callback results
  'get_field_descriptions': (namelist, callback) ->
    field_info <- get_field_info()
    output = {}
    for x in namelist
      if field_info[x]? and field_info[x].description?
        output[x] = field_info[x].description
    callback output
}

confirm_permissions = (info, callback) ->
  {pagename, fieldnames} = info
  field_info <- get_field_info()
  field_info_list = []
  for x in fieldnames
    output = {name: x}
    if field_info[x]? and field_info[x].description?
      output.description = field_info[x].description
    field_info_list.push output
  sendTab 'confirm_permissions', {pagename, fields: field_info_list}, callback

chrome.tabs.onUpdated.addListener (tabId, changeInfo, tab) ->
  if tab.url
    #console.log 'tabs updated!'
    #console.log tab.url
    if changeInfo.status != 'complete'
      return
    possible_interventions <- list_available_interventions_for_location(tab.url)
    if possible_interventions.length > 0
      chrome.pageAction.show(tabId)
    else
      chrome.pageAction.hide(tabId)
    #send_pageupdate_to_tab(tabId)
    load_intervention_for_location tab.url

chrome.runtime.onMessageExternal.addListener (request, sender, sendResponse) ->
  {type, data} = request
  message_handler = ext_message_handlers[type]
  if type == 'requestfields' or type == 'requestfields_uncached'
    # do not prompt for permissions for these urls
    whitelist = [
      'http://localhost:8080/previewdata.html'
      'http://tmi.netlify.com/previewdata.html'
      'https://tmi.netlify.com/previewdata.html'
      'https://tmi.stanford.edu/previewdata.html'
      'https://tmisurvey.herokuapp.com/'
      'http://localhost:8080/'
      'https://localhost:8081/'
      'https://tmi.stanford.edu/'
      'http://localhost:3000/'
      'http://browsingsurvey.herokuapp.com/'
      'https://browsingsurvey.herokuapp.com/'
      'http://browsingsurvey2.herokuapp.com/'
      'https://browsingsurvey2.herokuapp.com/'
      'http://browsingsurvey3.herokuapp.com/'
      'https://browsingsurvey3.herokuapp.com/'
      'http://browsingsurvey4.herokuapp.com/'
      'https://browsingsurvey4.herokuapp.com/'
      'http://browsingsurvey5.herokuapp.com/'
      'https://browsingsurvey5.herokuapp.com/'
      'http://browsingsurvey6.herokuapp.com/'
      'https://browsingsurvey6.herokuapp.com/'
      'http://browsingsurvey7.herokuapp.com/'
      'https://browsingsurvey7.herokuapp.com/'
      'http://browsingsurvey8.herokuapp.com/'
      'https://browsingsurvey8.herokuapp.com/'
      'http://browsingsurvey9.herokuapp.com/'
      'https://browsingsurvey9.herokuapp.com/'
      'http://browsingsurvey10.herokuapp.com/'
      'https://browsingsurvey10.herokuapp.com/'
      'http://browsingsurvey11.herokuapp.com/'
      'https://browsingsurvey11.herokuapp.com/'
      'http://browsingsurvey12.herokuapp.com/'
      'https://browsingsurvey12.herokuapp.com/'
      'http://browsingsurvey13.herokuapp.com/'
      'https://browsingsurvey13.herokuapp.com/'
    ]
    for whitelisted_url in whitelist
      if sender.url.indexOf(whitelisted_url) == 0
        message_handler = message_handlers[type]
        break
  if not message_handler?
    return
  #tabId = sender.tab.id
  message_handler data, (response) ~>
    #console.log 'response is:'
    #console.log response
    #response_string = JSON.stringify(response)
    #console.log 'length of response_string: ' + response_string.length
    #console.log 'turned into response_string:'
    #console.log response_string
    if sendResponse?
      sendResponse response
  return true # async response

chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
  {type, data} = request
  console.log 'onmessage'
  console.log type
  console.log data
  message_handler = message_handlers[type]
  if not message_handler?
    return
  # tabId = sender.tab.id
  message_handler data, (response) ->
    #console.log 'message handler response:'
    #console.log response
    #response_data = {response}
    #console.log response_data
    # chrome bug - doesn't seem to actually send the response back....
    #sendResponse response_data
    if sendResponse?
      sendResponse response
    # {requestId} = request
    # if requestId? # response requested
    #  chrome.tabs.sendMessage tabId, {event: 'backgroundresponse', requestId, response}
  return true


# open the options page on first run
#chrome.tabs.create {url: 'options.html'}
