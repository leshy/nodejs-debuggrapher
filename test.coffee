dgram = require 'dgram'
helpers = require 'helpers'
send = (n) -> 

    message = new Buffer JSON.stringify { stream: 'blax', value: n }
    client = dgram.createSocket "udp4"
    client.send message, 0, message.length, 41234, "localhost", (err, bytes) -> client.close()



randomWalk = (last) ->
    if not last then last = 0
    return last + helpers.randrange(10) - 5 + ((10 - last) / 20)

last = 0
booyah = ->
    send(last = randomWalk(last))
    setTimeout booyah, 30

booyah()