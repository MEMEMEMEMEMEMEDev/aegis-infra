// __ORG__-app — the initial HTTP service of the __ORG__ organization.
//
// It was born from aegis's `service-java` template and from that moment
// on it is YOURS: the template never touches it again. Zero external
// dependencies on purpose (the JDK's own HTTP server is enough to
// serve): an empty dependency tree is a tree that does not rot, and
// nothing here has to be explained to Trivy.
//
// The only thing the platform asks of this process is that it listen on
// the port the contract declares (8080, and on 0.0.0.0 — a server bound
// to localhost is unreachable from the kubelet's probe and from the
// edge) and answer /healthz, which the readinessProbe polls.
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public class App {

    static final int PORT = 8080;

    /** The whole app, kept apart from the server so the tests can call
     *  it without binding a port. */
    public static String respond(String path) {
        if ("/healthz".equals(path)) {
            return "ok\n";
        }
        return "__ORG__ — initial app of the service-java template, pod "
               + System.getenv().getOrDefault("HOSTNAME", "?") + "\n";
    }

    static void handle(HttpExchange x) throws IOException {
        byte[] body = respond(x.getRequestURI().getPath())
                .getBytes(StandardCharsets.UTF_8);
        x.getResponseHeaders().add("content-type", "text/plain; charset=utf-8");
        x.sendResponseHeaders(200, body.length);
        try (OutputStream out = x.getResponseBody()) {
            out.write(body);
        }
    }

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", PORT), 0);
        server.createContext("/", App::handle);
        // The default executor serves one request at a time; a pool of
        // platform threads is what makes a slow upstream stop blocking
        // the readinessProbe.
        server.setExecutor(java.util.concurrent.Executors.newFixedThreadPool(8));
        server.start();
    }
}
