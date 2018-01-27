module Merly
import HttpServer.mimetypes
import Base.|

using HttpServer,
      HttpCommon,
      JSON,
      XMLDict

include("routes.jl")
include("allformats.jl")
include("webserver.jl")

export app, @page, @route, GET,POST,PUT,DELETE,HEAD,OPTIONS,PATCH,Get,Post,Put,Delete,routes

cors=false::Bool

root=pwd()
if root[end]=='/'
  root=root[1:end-1]
elseif is_windows() && root[end]=='\\'
  root=root[1:end-1]
end

exten="\"\""::AbstractString

type Q
  query
  params
  body::AbstractString
  notfound_message::AbstractString
end

global q=Q(Dict(),Dict(),"","NotFound")

type Fram
  notfound::Function
  start::Function
  useCORS::Function
  webserverfiles::Function
  webserverpath::Function
end

function _body(data::Array{UInt8,1},format::String)
  content=""
  for i=1:length(data)
   content*="$(Char(data[i]))"
  end
  return getindex(formats, format)(content)
end

function File(file::String)
  try
    path = normpath(root, file)
    return readstring(path)
  catch
    return file
  end
end

function resolveroute(ruta::String)
  for key in keys(routes_patterns)
    params= match(key,ruta)
    if params!= nothing
      return params, getindex(routes_patterns,key)
    end
  end
end

function processroute_pattern(searchroute::String,request::HttpCommon.Request,response::HttpCommon.Response)
  q.params, _function  = resolveroute(searchroute)
  respond = _function(q,request,response)
  sal = matchall(Regex("{{([a-z])+}}"),respond)
  for i in sal
    respond = replace(respond,Regex(i),q.params["$(i[3:end-2])"])
  end
  return respond
end

function handler(request::HttpCommon.Request,response::HttpCommon.Response)

  data = split(request.resource,"?")
  url=data[1]

  searchroute = request.method*url

  try
    q.query= parsequerystring(data[2]);
  end

  try
    q.body = _body(request.data,request.headers["Content-Type"])
  catch
    q.body = _body(request.data,"*/*")
  end

  if cors
   response.headers["Access-Control-Allow-Origin"]="*"
   response.headers["Access-Control-Allow-Methods"]="POST,GET,OPTIONS"
  end

  info("METODO : ",request.method,"    URL : ",url)

  try
    response.data = getindex(routes, searchroute)(q,request,response)
  catch
    try
      response.data = processroute_pattern(searchroute,request,response)
    catch
      response.data = getindex(routes, "notfound")(q,request,response)
    end
  end

  return response
end


# funcion debug
# ipv 6
# CRTL Z  para matar proceso
function app()
global root
global exten
global cors

  function useCORS(activate::Bool)
      cors=activate
  end

  function notfound(text::AbstractString)
      q.notfound_message= File(text)
  end

  function webserverfiles(load::AbstractString)
      if load=="*"
        WebServer(root)
      else
        exten=load::AbstractString
        WebServer(root)
      end
  end

  function webserverpath(path::AbstractString)
      root= path
      #cd(root)
  end

  function start(host="0.0.0.0"::AbstractString,port=8000::Integer)
    http = HttpHandler((req, res)-> handler(req,res))
    http.events["error"]  = (client, error) -> println(error)
    http.events["listen"] = (port)          -> println("Listening on $port...")
    server = Server(http)
    if host=="localhost"
      host="127.0.0.1"
    end
    try
      #@async run(server, host=IPv4(host), port=port)
      run(server, host=IPv4(host), port=port)
    catch
      try
        run(server, host=IPv6(host), port=port)
      catch
        warn("Address not valid, check it")
      end
    end
  end

  return Fram(notfound,start,useCORS,webserverfiles,webserverpath)
end
end # module
