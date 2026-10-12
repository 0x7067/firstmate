import http.server, ssl, sys, json
class API(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        print('GraphQL query received by disposable API', flush=True)
        body=json.dumps({'data': {'repository': {'pullRequest': {'state': 'MERGED'}}}}).encode()
        self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *args): pass
class Proxy(http.server.BaseHTTPRequestHandler):
    def do_CONNECT(self):
        self.send_response(200); self.end_headers()
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(sys.argv[1], sys.argv[2])
        secure=context.wrap_socket(self.connection, server_side=True)
        API(secure, self.client_address, self.server)
    def log_message(self, *args): pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Proxy)
with open(sys.argv[3],'w') as port: port.write(str(server.server_port))
server.serve_forever()
