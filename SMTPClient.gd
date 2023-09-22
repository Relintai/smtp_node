extends Node

enum SMTPStatus {
	OK,
	WAITING,
	NO_RESPONSE,
	UNHANDLED_REPONSE
}

enum AuthType {
	SMTPS, # SMTPS server, connect, adn immediately just upgrade to use SSL
	STARTTLS, # SMTP + STARTTLS server Connect, then upgrade to SSL using a command before auth
	PLAINTEXT, # No SSL
}

export(String) var smtp_server : String = ""
export(int) var smtp_server_port : int = 465

export(String) var user : String = ""
export(String) var password : String = ""
export(String) var sender_email_address : String = ""
export(String) var sender_name : String = ""

# This is sent to the SMTP server at login to id a client, can be anything
export(String) var smtp_client_address : String = "client.example.com"

export(int) var max_retries : int = 5
export(int) var delay_time : int = 250
export(AuthType) var auth_type : int = 0

var _socket_original : StreamPeer = null
var _socket : StreamPeer = null
var _packet_in : String = ""
var _packet_out : String = ""

var _current_status : int = 0

var _thread : Thread = null
var _thread_semaphore : Semaphore = Semaphore.new()
var _thread_running : bool = true

var _mail_queue : Array = Array()
var _mail_queue_lock : Mutex = Mutex.new()

var _auth_login_base64 : String = ""
var _auth_pass_base64 : String = ""

func _ready():
	if user != "":
		_auth_login_base64 = Marshalls.raw_to_base64(user.to_ascii())
		
	if password != "":
		_auth_pass_base64 = Marshalls.raw_to_base64(password.to_ascii())

func _enter_tree() -> void:
	_thread_running = true
	_thread = Thread.new()
	_thread.start(self, "_thread_main_loop", null)
	
func _exit_tree() -> void:
	_thread_running = false
	_thread_semaphore.post()
	_thread.wait_to_finish()
	_thread = null

func send_mail(address, subject, data):
	_mail_queue_lock.lock()
	_mail_queue.append([address, subject, data])
	_mail_queue_lock.unlock()
	
	_thread_semaphore.post()

func _thread_main_loop(user_data):
	while _thread_running:
		_mail_queue_lock.lock()
		
		if _mail_queue.size() > 0:
			var md = _mail_queue.pop_front()
			_mail_queue_lock.unlock()
			
			_thread_deliver(md)
		else:
			_mail_queue_lock.unlock()
		
		if _mail_queue.size() == 0:
			_thread_semaphore.wait()

func _thread_deliver(user_data):
	var address : String = user_data[0]
	var subject : String = user_data[1]
	var data : String = user_data[2]
	
	var r_code : int
	r_code = open_socket()
	
	if r_code == OK:
		r_code = wait_answer()
#	if r_code == OK:
#		emit_signal("SMTP_connected")
#		r_code = send("ciao") # needed because some SMTP servers return error each first command
	if r_code == OK:
		r_code = mail_hello()
	if r_code == OK && auth_type == AuthType.STARTTLS:
		r_code = mail_starttls()
		if r_code == OK:
			r_code = mail_hello()
	if r_code == OK:
		r_code = mail_auth()
	if r_code == OK:
		r_code = mail_from(sender_email_address)
	if r_code == OK:
		r_code = mail_to(address)
	if r_code == OK:
		r_code = mail_data(data, subject)
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


func open_socket():
	var error : int

	if _socket == null:
		_socket = StreamPeerTCP.new()
		error = _socket.connect_to_host(smtp_server, smtp_server_port)
		
	display(["connecting server...", smtp_server,error])

	if error > 0:
		var ip = IP.resolve_hostname(smtp_server)
		error=_socket.connect_to_host(ip, smtp_server_port)
		display(["trying IP ...",ip,error])

	for i in range(1, max_retries):
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
	
	if auth_type == AuthType.SMTPS:
		_socket_original = _socket
		
		_socket = StreamPeerSSL.new()
		_socket.connect_to_stream(_socket_original, true, smtp_server)
			
		for i in range(max_retries):
			print("TLS RETRIES" + str(_socket.get_status()))
			
			if _socket.get_status() == _socket.STATUS_ERROR:
				display("Error while requesting connection")
				return _socket.get_status()
				
	#		elif _socket.get_status() == _socket.STATUS_CONNECTING:
	#			d.display("connecting...")
	#			break
		
			if _socket.get_status() == _socket.STATUS_CONNECTED:
				display("TLS connection up")
				print("TLS CONNECTED")
				break
				
			OS.delay_msec(delay_time)

	return error

func close_socket():
	if !_socket_original:
		_socket.disconnect_from_host()
	else:
		_socket.disconnect_from_stream()
		_socket_original.disconnect_from_host()
		
	_socket = null
	_socket_original = null

func send(data1,data2=null,data3=null):
	return send_only(data1,data2,data3)

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
	for i in range(max_retries):
		if _socket.has_method(@"poll"):
			_socket.poll()
			
		var buf_len = _socket.get_available_bytes()
		if buf_len > 0:
			display(["bytes buffered",String(buf_len)])
			_packet_in = _packet_in + _socket.get_utf8_string(buf_len)
			display(["receive",_packet_in])
			
			break
		else:
			OS.delay_msec(delay_time)
	
	# This will likely need a rework
	if _packet_in != "":
		_current_status = SMTPStatus.OK
		if parse_packet_in(succesful) != OK:
			_current_status = SMTPStatus.UNHANDLED_REPONSE
	else:
		_current_status = SMTPStatus.NO_RESPONSE
		
	return _current_status


func parse_packet_in(strcompare : String):
	if strcompare == "":
		return OK
		
	var slicecount : int = _packet_in.get_slice_count("\r\n")

	if slicecount <= 1:
		if _packet_in.left(strcompare.length()) == strcompare:
			return OK
		else:
			return FAILED
	else:
		var ll : String = _packet_in.get_slice("\r\n", slicecount - 2)
		if ll.left(strcompare.length()) == strcompare:
			return OK
		else:
			return FAILED

func mail_hello():
	var r_code : int = send("HELO", smtp_client_address)
	wait_answer()
	r_code= send("EHLO", smtp_client_address)
	r_code= wait_answer("250")
	return r_code

func mail_starttls():
	var r_code : int = send("STARTTLS")
	r_code = wait_answer("220") #220 TLS go ahead
	
	if r_code != OK:
		return r_code
	
	_socket_original = _socket
	
	_socket = StreamPeerSSL.new()
	_socket.connect_to_stream(_socket_original, true, smtp_server)
		
	for i in range(max_retries):
		print("STARTTLS RETRIES" + str(_socket.get_status()))
		
		if _socket.get_status() == _socket.STATUS_ERROR:
			display("Error while requesting connection")
			return _socket.get_status()
			
#		elif _socket.get_status() == _socket.STATUS_CONNECTING:
#			d.display("connecting...")
#			break
	
		if _socket.get_status() == _socket.STATUS_CONNECTED:
			display("STARTTLS connection up")
			print("STARTTLS CONNECTED")
			break
			
		OS.delay_msec(delay_time)
	
	return r_code

func mail_auth():
	var r_code : int =send("AUTH LOGIN")
	r_code=wait_answer("334")
	
	#print("mail_auth()  , AUTH LOGIN ", r_code) 

	if r_code == OK:
		r_code=send(_auth_login_base64)
		
	r_code = wait_answer("334")
	
	#print("mail_auth()  , username ", r_code)
	
	if r_code == OK:
		r_code=send(_auth_pass_base64)
		
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
	

func mail_data(data=null,subject=null):
	var corpo : String = data
	corpo += "\r\n.\r\n"
	
	var r_code=send("DATA")
	r_code=wait_answer("354")
	if r_code == OK:
		r_code=send("FROM: ", sender_name + " " + bracket(sender_email_address))
		#r_code =wait_answer("250")
	if r_code == OK and subject != null:
		r_code=send("SUBJECT: ",subject)
		#r_code =wait_answer("250")
	if r_code == OK and data != null:
		r_code=send(corpo)
		#r_code =wait_answer("250")
		
	r_code = wait_answer("250")
	
	return r_code

func mail_quit():
	return send("QUIT")

func bracket(data):
	return "<"+data+">"

func _on_Button_pressed() -> void:
	send_mail("", "TEST SUBJECT", "TEST MSG!")

var debug = true
func display(data):
	if debug == true:
		print("debug: ",data)
