extends Node

export var server : String = "smtp.gmail.com" 
export var port : int = 465
export var user : String = ""
export var password : String = ""
export var max_retries : int = 5
export var delay_time : int = 250

export var mymailto = ""
export var mymail = "mail.smtp.localhost"

var _socket_original = null
var _socket = null
var _packet_in = ""
var _packet_out = ""

var subject = "New message from Godot"

enum SMTPStatus {
	OK,
	WAITING,
	NO_RESPONSE,
	UNHANDLED_REPONSE
}

var _current_status : int = 0

var thread : Thread = null

var authloginbase64 : String  = ""
var authpassbase64 : String = ""

func _ready():
	if user != "":
		authloginbase64 = Marshalls.raw_to_base64(user.to_ascii())
		
	if password != "":
		authpassbase64 = Marshalls.raw_to_base64(password.to_ascii())
  
func deliver(data):
	thread = Thread.new()
	thread.start(self,"thread_deliver",data)

func thread_deliver(data):
	var r_code
	r_code = Open_socket()
	if r_code == OK:
		r_code = wait_answer()
#	if r_code == OK:
#		emit_signal("SMTP_connected")
#		r_code = send("ciao") # needed because some SMTP servers return error each first command
	if r_code == OK:
		r_code = mail_hello()
	if r_code == OK:
		print("SMTP_working")
		close_socket()
		return
		r_code = mail_auth()
	if r_code == OK:
		r_code = mail_from(mymail)
	if r_code == OK:
		r_code = mail_to(mymailto)
	if r_code == OK:
		r_code = mail_data(data,mymail,subject)
	if r_code == OK:
		print("process OK")
	if r_code == OK:
		r_code = mail_quit()
	close_socket()
	if r_code == OK:
		display("All done")
	else:
		display("ERROR " + str(r_code))
	return r_code


func Open_socket():
	var error : int

	if _socket_original == null:
		_socket_original = StreamPeerTCP.new()
		error = _socket_original.connect_to_host(server,port)
		
		_socket = StreamPeerSSL.new()
		_socket.connect_to_stream(_socket_original, true, server)

	display(["connecting server...",server,error])

	if error > 0:
		var ip=IP.resolve_hostname(server)
		error=_socket.connect_to_host(ip,port)
		display(["trying IP ...",ip,error])

	for i in range(1,max_retries):
		print("RETRIES" + str(_socket.get_status()))
		
#		if _socket.get_status() == _socket.STATUS_ERROR:
#			d.display("Error while requesting connection")
#			break
#		elif _socket.get_status() == _socket.STATUS_CONNECTING:
#			d.display("connecting...")
#			break

		if _socket.get_status() == _socket.STATUS_CONNECTED:
			display("connection up")
			print("CONNECTED")
			break
			
		OS.delay_msec(delay_time)
		
	return error

func close_socket():
	_socket_original.disconnect_from_host()

func send(data1,data2=null,data3=null):
	var error
	error = send_only(data1,data2,data3)
	return error

func send_only(data1,data2=null,data3=null):
	var error = 0
	_packet_out = data1
	if data2 != null:
		_packet_out = _packet_out + " " + data2
	if data3 != null:
		_packet_out = _packet_out + " " + data3
	display(["send",_packet_out])
	_packet_out = _packet_out + "\n"

	error=_socket.put_data(_packet_out.to_utf8())
	if error == null:
		error = "NULL"
		
	display(["send","r_code",error])
	
	return error

func wait_answer(succesful=""):
	_current_status= SMTPStatus.WAITING
	display(["waiting response from server..."])

	_packet_in = ""
	OS.delay_msec(delay_time)
	for i in range(1,max_retries):
		_socket.poll()
		var bufLen = _socket.get_available_bytes()
		if bufLen > 0:
			display(["bytes buffered",String(bufLen)])
			_packet_in=_packet_in + _socket.get_utf8_string(bufLen)
			display(["receive",_packet_in])
			
			break
		else:
			OS.delay_msec(delay_time)
	if _packet_in != "":
		_current_status= SMTPStatus.OK
		if parse_packet_in(succesful) != OK:
			_current_status=SMTPStatus.UNHANDLED_REPONSE
	else:
		_current_status = SMTPStatus.NO_RESPONSE
	return _current_status


func parse_packet_in(strcompare):
	if strcompare == "":
		return OK
	if _packet_in.left(strcompare.length())==strcompare:
		return OK
	else:
		return FAILED

func mail_hello():
	var r_code=send("HELO", mymail)
	wait_answer()
	r_code= send("EHLO", mymail)
	r_code= wait_answer("250")
	return r_code

# the mail_auth() function was broken, I fixed it, you're welcome
func mail_auth():
	var r_code=send("AUTH LOGIN")
	r_code=wait_answer("334")
	
	#print("mail_auth()  , AUTH LOGIN ", r_code) 
	# when debugging, add print statements everywhere you fail to progress.

	if r_code == OK:
		r_code=send(authloginbase64)
	r_code = wait_answer("334")
	#print("mail_auth()  , username ", r_code)
	if r_code == OK:
		r_code=send(authpassbase64)
		
	r_code = wait_answer("235")
	#print("mail_auth()  , password ", r_code)
	display(["r_code auth:", r_code])
	return r_code

func mail_from(data):
	var r_code=send("MAIL FROM:",bracket(data))
	r_code = wait_answer("250")
	return r_code

func mail_to(data):
	var r_code=send("RCPT TO:",bracket(data))
	r_code = wait_answer("250")
	return r_code
	

func mail_data(data=null,from=null,subject=null):
	var corpo = ""
	for i in data:
		corpo = corpo + i  + "\r\n"
	corpo=corpo + "."
	var r_code=send("DATA") 
	r_code=wait_answer("354")
#	if r_code == OK and from != null:
#		r_code=send("FROM: ",bracket(from))
	if r_code == OK and subject != null:
		r_code=send("SUBJECT: ",subject)
	if r_code == OK and data != null:
		r_code=send(corpo)
	r_code =wait_answer("250")
	return r_code

func mail_quit():
	return send("QUIT")

func bracket(data):
	return "<"+data+">"

func _on_Button_pressed() -> void:
	deliver("TEST MSG!")

var debug = true
func display(data):
	if debug == true:
		print("debug: ",data)
