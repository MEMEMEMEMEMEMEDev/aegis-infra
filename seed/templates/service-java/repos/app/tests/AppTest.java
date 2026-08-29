// The suite the Containerfile runs. It is the image's only gate: if it
// goes red the build stops and no image is produced.
//
// Plain assertions and a main(), not JUnit: a test framework is a
// dependency to download, pin and scan, and this template starts with
// none. Swap it for JUnit the day you adopt a build tool.
public class AppTest {

    static void check(boolean ok, String what) {
        if (!ok) {
            System.err.println("FAIL: " + what);
            System.exit(1);
        }
        System.out.println("ok: " + what);
    }

    public static void main(String[] args) {
        // The readinessProbe polls this path: if it stops answering,
        // the pod never becomes ready and the deploy hangs with no
        // error anywhere.
        check("ok\n".equals(App.respond("/healthz")), "/healthz answers ok");
        check(App.respond("/").contains("__ORG__"), "the root names the organization");
    }
}
