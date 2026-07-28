component extends="coldbox.system.Bootstrap" {

    this.name = "TaborLane";
    this.applicationTimeout = createTimeSpan( 1, 0, 0, 0 );
    this.sessionManagement = true;
    this.sessionTimeout = createTimeSpan( 0, 2, 0, 0 );
    this.setClientCookies = true;
    this.setDomainCookies = false;

    COLDBOX_APP_ROOT_PATH = getDirectoryFromPath( getCurrentTemplatePath() );
    COLDBOX_APP_MAPPING = "";
    COLDBOX_CONFIG_FILE = "";
    COLDBOX_APP_KEY = "";

    variables.environment = server.system.environment;
    variables.dbHost = variables.environment.DB_HOST ?: "postgres";
    variables.dbPort = variables.environment.DB_PORT ?: "5432";
    variables.dbName = variables.environment.DB_NAME ?: "tabor_lane";
    variables.dbUser = variables.environment.DB_USER ?: "tabor_lane";
    variables.dbPassword = variables.environment.DB_PASSWORD ?: "tabor_lane_local";
    variables.dbSslMode = variables.environment.DB_SSL_MODE ?: "disable";

    this.datasource = "taborLane";
    this.datasources = {
        "taborLane" = {
            class = "org.postgresql.Driver",
            bundleName = "org.postgresql.jdbc",
            connectionString = "jdbc:postgresql://#variables.dbHost#:#variables.dbPort#/#variables.dbName#?sslmode=#variables.dbSslMode#",
            username = variables.dbUser,
            password = variables.dbPassword,
            connectionLimit = 20,
            connectionTimeout = 10,
            timezone = "UTC"
        }
    };

}
