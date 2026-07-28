component singleton {

	variables.environment = server.system.environment;
	variables.apiKey = variables.environment.BREVO_API_KEY ?: "";
	variables.senderEmail = variables.environment.BREVO_SENDER_EMAIL ?: "notifications@taborlane.local";
	variables.senderName = variables.environment.BREVO_SENDER_NAME ?: "Tabor Lane";

	boolean function isConfigured(){
		return variables.apiKey.len() > 0;
	}

	boolean function send(
		required string recipientEmail,
		string recipientName = "",
		required string subject,
		required string htmlContent,
		required string textContent
	){
		if ( !isConfigured() ) {
			writeLog(
				file = "application",
				type = "information",
				text = "Brevo is not configured; skipped email to #arguments.recipientEmail#: #arguments.subject#"
			);
			return false;
		}

		var payload = {
			sender = { name = variables.senderName, email = variables.senderEmail },
			to = [ { email = arguments.recipientEmail, name = arguments.recipientName } ],
			subject = arguments.subject,
			htmlContent = arguments.htmlContent,
			textContent = arguments.textContent
		};
		var response = {};

		try {
			cfhttp(
				method = "POST",
				url = "https://api.brevo.com/v3/smtp/email",
				result = "response",
				timeout = 12
			) {
				cfhttpparam( type = "header", name = "accept", value = "application/json" );
				cfhttpparam( type = "header", name = "api-key", value = variables.apiKey );
				cfhttpparam( type = "header", name = "content-type", value = "application/json" );
				cfhttpparam( type = "body", value = serializeJSON( payload ) );
			}
			if ( left( response.statusCode ?: "", 1 ) == "2" ) {
				return true;
			}
			writeLog(
				file = "application",
				type = "error",
				text = "Brevo rejected email with status #response.statusCode ?: 'unknown'#."
			);
		} catch ( any exception ) {
			writeLog(
				file = "application",
				type = "error",
				text = "Brevo email request failed: #exception.message#"
			);
		}
		return false;
	}

}
