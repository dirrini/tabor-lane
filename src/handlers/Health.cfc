component {

    function live( event, rc, prc ) {
        event.renderData(
            type = "json",
            data = {
                status = "ok",
                service = "tabor-lane"
            }
        );
    }

    function ready( event, rc, prc ) {
        try {
            var result = queryExecute(
                "SELECT 1 AS healthy",
                {},
                { datasource = "taborLane" }
            );

            event.renderData(
                type = "json",
                data = {
                    status = result.healthy[ 1 ] == 1 ? "ready" : "unavailable",
                    database = "connected"
                }
            );
        } catch ( any exception ) {
            event.renderData(
                type = "json",
                statusCode = 503,
                data = {
                    status = "unavailable",
                    database = "disconnected"
                }
            );
        }
    }

}

