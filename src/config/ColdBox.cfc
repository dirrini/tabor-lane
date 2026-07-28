component {

    function configure() {
        variables.coldbox = {
            appName = "Tabor Lane",
            eventName = "event",
            defaultEvent = "Home.index",
            exceptionHandler = "",
            onInvalidEvent = "",
            handlerCaching = false,
            eventCaching = false,
            reinitPassword = "",
            flash = {
                scope = "session",
                properties = {}
            }
        };

        variables.settings = {
            appEnvironment = server.system.environment.APP_ENV ?: "development",
            supportedLocales = [ "en_US", "pt_BR" ]
        };

        variables.layoutSettings = {
            defaultLayout = "Main.cfm"
        };

        variables.interceptors = [
            { class = "interceptors.I18nBootstrap" }
        ];

        variables.moduleSettings = {
            cbi18n = {
                defaultResourceBundle = "includes/i18n/main",
                defaultLocale = "en_US",
                localeStorage = "cookieStorage@cbstorages",
                unknownTranslation = "**MISSING TRANSLATION**",
                logUnknownTranslation = true
            },
            qb = {
                defaultGrammar = "PostgresGrammar@qb"
            }
        };

        variables.environments = {
            development = "development",
            production = "production"
        };
    }

    function development() {
        variables.coldbox.handlerCaching = false;
        variables.coldbox.eventCaching = false;
    }

    function production() {
        variables.coldbox.handlerCaching = true;
        variables.coldbox.eventCaching = true;
    }

}
