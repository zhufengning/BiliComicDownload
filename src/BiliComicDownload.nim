import httpClient, json, strutils, os, streams, bitops
import nim_miniz

var client = newHttpClient()
var 
  #userName, passWd, apiUrl :string
  sessdata, bookId, downList, downDir: string
  books, eps: JsonNode
  downArray: seq[string]

const
  api_mybooks = "https://manga.bilibili.com/twirp/bookshelf.v1.Bookshelf/ListFavorite?device=pc&platform=web"
  api_eplist = "https://manga.bilibili.com/twirp/comic.v2.Comic/ComicDetail?device=pc&platform=web"
  api_imgIndex = "https://manga.bilibili.com/twirp/comic.v1.Comic/GetImageIndex?device=pc&platform=web"
  api_imgToken = "https://manga.bilibili.com/twirp/comic.v1.Comic/ImageToken?device=pc&platform=web"

proc getInf: bool
proc getBookList: bool
proc getEpList: bool
proc downEp(epId: JsonNode): bool

when isMainModule:
  if getInf():
    if getBookList():
      echo "选择一项："
      bookId = $books["data"][parseInt(readLine(stdin)) - 1]["comic_id"]
      bookId = bookId.replace("\"", "")
      if getEpList():
        echo "想下载哪些？（未付费章节将自动忽略）"
        echo "输入格式：1,2,3,4-10"
        echo "格式错误会发生奇怪的事情"
        downList = readLine(stdin)
        downArray = downList.split(",")
        echo "保存在哪个文件夹呢？"
        downDir = readLine(stdin)
        if downDir[downDir.len - 1] != '/' and downDir[downDir.len - 1] != '\\':
          downDir.add("/")

        for i in downArray:
          var t = i.split("-")
          if t.len == 1:
            if downEp(eps[eps.len - parseInt(t[0])]) == false:
              echo t[0], "话下载失败"
          else:
            for i in countdown(eps.len - parseInt(t[0]), eps.len - parseInt(t[1])):
              if downEp(eps[i]) == false:
                echo eps.len - i, "话下载失败"
  removeFile("tmp.zip")
  removeFile("index.dat")



proc getInf(): bool =
  #[
  echo "Please input your username:"
  userName = readLine(stdin)
  echo "Please input your password:"
  passWd = readLine(stdin)
  echo "Please input the url of BiliComicWebReader, enter 'h' for help"
  apiUrl = readLine(stdin)
  if apiUrl == "h":
    echo "https://gist.github.com/esterTion/292e27b97884dfa58542308dd896ce38"
    echo "Because I'm to lazy to build a wheel, so a server with this is needed"
    return false 
  else:
    return true
  ]#
  echo "输入你的SESSDATA:（用浏览器登录后F12看Cookie）"
  sessdata = readLine(stdin)
  return true


proc getBookList(): bool =
  echo "开始获取追漫列表。。。"
  client.headers = newHttpHeaders({
    "Cookie": "SESSDATA=" & sessdata & ";", 
    "Content-Type": "application/json;charset=utf-8", 
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:70.0) Gecko/20100101 Firefox/70.0", 
    "Accept": "application/json, text/plain, */*", 
    "Accept-Language": "zh-CN", 
    "Referer": "https://manga.bilibili.com/account-center"})
  let bd = """{"page_num":1,"page_size":15,"order":1,"wait_free":0}"""
  let res = client.request(api_mybooks, httpMethod = HttpPost, body = bd)
  if res.status != "200 OK":
    echo "请求失败：", res.status
    return false
  books = parseJson(res.body)
  var cnt = 1;
  for i in books["data"]:
    echo cnt, ":", i["title"]
    cnt += 1;
  return true
  
proc getEpList(): bool =
  echo "获取章节列表。。。"
  let bd = """{"comic_id":""" & bookId & """}"""
  # echo bd
  let res = client.request(api_eplist, httpMethod = HttpPost, body = bd)
  if res.status != "200 OK":
    echo "请求失败：", res.status
    return false
  # echo res.body
  eps = parseJson(res.body)["data"]["ep_list"]
  if eps.len <= 0:
    echo "为什么一话都没有呢嘤嘤嘤"
    return false
  else:
    echo "获取到", eps.len, "话"
    return true


proc downEp(epId: JsonNode): bool =
  var
    path, bd: string
    resj, pics: JsonNode
  if epId["is_locked"].getBool == true:
    echo "你好像忘记充钱了"
    return false
  path = downDir & replace($epId["short_title"] & "-" & $epId["title"], "\"", "") & "/"
  # echo path
  if existsDir(path) == false:
    createDir(path)
  
  downloadFile(client, replace($epId["cover"], "\"", ""), path & "0 Cover.jpg")
  bd = """{"ep_id":""" & replace($epId["id"], "\"", "") & "}"
  var res = client.request(api_imgIndex, httpMethod = HttpPost, body = bd)
  if res.status != "200 OK":
    echo "请求失败：", res.status
    return false
  resj = parseJson(res.body)
  let zipUrl = replace(replace($resj["data"]["host"] & $resj["data"]["path"], "\"", ""), "\\u0026", "&")


  # 开始解密（懒得写成单独的函数了）
  # 参考：https://github.com/flaribbit/bilibili-manga-spider/（可读性极强，别看我，看他）
  var fucking = client.request(zipUrl).body
  var fuckStream = newStringStream(fucking[9..^1])
  var data: seq[byte]
  var tmp: byte
  # data.setLen(len(fucking))
  while fuckStream.atEnd == false:
    discard fuckStream.readData(addr(tmp), 1)
    data.add(tmp)
  var cid, eid: uint32
  cid = uint32(parseInt(bookId))
  eid = uint32(parseInt(($epId["id"]).replace("\"", "")))
  var key: array[8, uint32]
  key = [(bitand(eid, 0xff)), (bitand(rotateRightBits(eid, 8), 0xff)), (bitand(rotateRightBits(eid, 16), 0xff)), (bitand(rotateRightBits(eid, 24), 0xff))
  , (bitand(cid, 0xff)), (bitand(rotateRightBits(cid, 8), 0xff)), (bitand(rotateRightBits(cid, 16), 0xff)), (bitand(rotateRightBits(eid, 24), 0xff))]
  for i in countup(0, len(data) - 1):
    data[i] = byte(bitxor(uint32(data[i]), key[i mod 8]))
  var f:File
  if f.open("tmp.zip", fmWrite):
    var fst = newFileStream(f)
    for i in data:
      var b = i
      fst.writeData(addr(b), 1)

    fst.close()
    var zip:Zip
    zip.open("tmp.zip")
    if (f.open(zip.extract_file("index.dat"), fmRead)):
      # 解密结束，开始读取地址
      pics = parseJson(f.readAll())["pics"]
      var plen = len(pics)
      var w = 0
      while plen > 0:
        w += 1
        plen = plen div 10
      var cnt = 0
      for k in pics:
        cnt += 1
        bd = """{"urls":"[\"""" & replace($k, "\"", "") & """\"]"}'"""
        let res = client.request(api_imgToken, httpMethod = HttpPost, body = bd)
        if res.status != "200 OK":
          echo "请求失败：", res.status
          return false
        let resj = parseJson(res.body)
        let picUrl = replace(replace(($resj["data"][0]["url"]) & "?token=" & ($resj["data"][0]["token"]), "\"", ""), "\\u0026", "&")
        var ws = 0
        var ncnt = cnt
        while ncnt > 0:
          ws += 1
          ncnt = ncnt div 10
        var fname = ""
        for i in countup(1, w - ws):
          fname.add('0')
        fname.add(replace($cnt, "\"", ""))
        fname.add(".jpg")
        echo path & fname
        downloadFile(client, picUrl, path & fname)
        echo "完成"
      return true
    else:
      echo "文件访问错误"
      return false
  else:
    echo "文件访问错误"
    return false