extends Node

export var server = "smtp.gmail.com" 
export var port	= 465
export var user = ""
export var password = ""
export var mymailto = ""
export var mymail = "mail.smtp.localhost"

enum channel {TCP,PACKET}
export (channel) var com = channel.TCP

var Bocket = null
var Socket = null
var PacketSocket = null
var PacketIn = ""
var PacketOut = ""

enum esi {OK,KO}    

enum stati {OK,WAITING,NO_RESPONSE,UNHANDLED_REPONSE}
export (stati) var stato

var MaxRetries = 5
var delayTime = 250

var thread = null

var authloginbase64=""
var authpassbase64=""

func _ready():
	if user != "":
		authloginbase64=Marshalls.raw_to_base64(user.to_ascii())
	if password != "":
		authpassbase64=Marshalls.raw_to_base64(password.to_ascii())
  

func Deliver(data):
	thread = Thread.new()
	thread.start(self,"ThreadDeliver",data)


# If you want to debug the program, this is where you start
# I made a miniscule change to this function, which was actually extremely hard, and took a few days.
func ThreadDeliver(data):
	var r_code
	r_code = OpenSocket()
	if r_code == OK:
		r_code =WaitAnswer()
#	if r_code == OK:
#		emit_signal("SMTP_connected")
#		r_code = send("ciao") # needed because some SMTP servers return error each first command
	if r_code == OK:
		r_code = MAILhello()
	if r_code == OK:
		print("SMTP_working")
		CloseSocket()
		return
		r_code = MAILauth()
	if r_code == OK:
		r_code = MAILfrom(mymail)
	if r_code == OK:
		r_code = MAILto(mymailto)
	if r_code == OK:
		r_code = MAILdata(data,mymail,subject)
	if r_code == OK:
		print("process OK")
	if r_code == OK:
		r_code =MAILquit()
	CloseSocket()
	if r_code == OK:
		display("All done")
	else:

		display("ERROR " + str(r_code))
	return r_code


func OpenSocket():
	var error

	if Bocket == null:
		Bocket=StreamPeerTCP.new()
		error=Bocket.connect_to_host(server,port)
		Socket = StreamPeerSSL.new()
		Socket.connect_to_stream(Bocket, true, server)

	display(["connecting server...",server,error])

	if error > 0:
		var ip=IP.resolve_hostname(server)
		error=Socket.connect_to_host(ip,port)
		display(["trying IP ...",ip,error])

	for i in range(1,MaxRetries):
		print("asdasd" + str(Socket.get_status()))
		
#		if Socket.get_status() == Socket.STATUS_ERROR:
#			d.display("Error while requesting connection")
#			break
#		elif Socket.get_status() == Socket.STATUS_CONNECTING:
#			d.display("connecting...")
#			break

		if Socket.get_status() == Socket.STATUS_CONNECTED:
			display("connection up")
			print("CONNECTED")
			break
			
		OS.delay_msec(delayTime)
		
	return error

func CloseSocket():
	Bocket.disconnect_from_host()

func send(data1,data2=null,data3=null):
	var error
	error = sendOnly(data1,data2,data3)
	return error

func sendOnly(data1,data2=null,data3=null):
	var error = 0
	PacketOut = data1
	if data2 != null:
		PacketOut = PacketOut + " " + data2
	if data3 != null:
		PacketOut = PacketOut + " " + data3
	display(["send",PacketOut])
	PacketOut = PacketOut + "\n"

	if com == channel.TCP:
		error=Socket.put_data(PacketOut.to_utf8())
		if error == null:
			error = "NULL"
	display(["send","r_code",error])
	return error

func WaitAnswer(succesful=""):
	stato= stati.WAITING
	display(["waiting response from server..."])
	if com == channel.TCP:
		PacketIn = ""
		OS.delay_msec(delayTime)
		for i in range(1,MaxRetries):
			Socket.poll()
			var bufLen = Socket.get_available_bytes()
			if bufLen > 0:
				display(["bytes buffered",String(bufLen)])
				PacketIn=PacketIn + Socket.get_utf8_string(bufLen)
				display(["receive",PacketIn])
				
				break
			else:
				OS.delay_msec(delayTime)
		if PacketIn != "":
			stato= stati.OK
			if ParsePacketIn(succesful) != OK:
				stato=stati.UNHANDLED_REPONSE
		else:
			stato = stati.NO_RESPONSE
		return stato
	else:
		return 99

func ParsePacketIn(strcompare):
	if strcompare == "":
		return OK
	if PacketIn.left(strcompare.length())==strcompare:
		return OK
	else:
		return FAILED

func MAILhello():
	var r_code=send("HELO", mymail)
	WaitAnswer()
	r_code= send("EHLO", mymail)
	r_code= WaitAnswer("250")
	return r_code

# the MAILauth() function was broken, I fixed it, you're welcome
func MAILauth():
	var r_code=send("AUTH LOGIN")
	r_code=WaitAnswer("334")
	
	#print("MAILauth()  , AUTH LOGIN ", r_code) 
	# when debugging, add print statements everywhere you fail to progress.

	if r_code == OK:
		r_code=send(authloginbase64)
	r_code = WaitAnswer("334")
	#print("MAILauth()  , username ", r_code)
	if r_code == OK:
		r_code=send(authpassbase64)
	r_code = WaitAnswer("235")
	#print("MAILauth()  , password ", r_code)
	display(["r_code auth:", r_code])
	return r_code

func MAILfrom(data):
	var r_code=send("MAIL FROM:",bracket(data))
	r_code = WaitAnswer("250")
	return r_code

func MAILto(data):
	var r_code=send("RCPT TO:",bracket(data))
	r_code = WaitAnswer("250")
	return r_code
	
var subject = "New message from Godot"


func MAILdata(data=null,from=null,subject=null):
	var corpo = ""
	for i in data:
		corpo = corpo + i  + "\r\n"
	corpo=corpo + "."
	var r_code=send("DATA") 
	r_code=WaitAnswer("354")
#	if r_code == OK and from != null:
#		r_code=send("FROM: ",bracket(from))
	if r_code == OK and subject != null:
		r_code=send("SUBJECT: ",subject)
	if r_code == OK and data != null:
		r_code=send(corpo)
	r_code =WaitAnswer("250")
	return r_code

func MAILquit():
	return send("QUIT")

func bracket(data):
	return "<"+data+">"


func _on_Button_pressed() -> void:
	Deliver("TEST MSG!")

var debug = true
func display(data):
	if debug == true:
		print("debug: ",data)
