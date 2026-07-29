component singleton {

	property name="brevoEmailProvider" inject="BrevoEmailProvider";

	variables.environment = server.system.environment;
	variables.baseUrl = reReplace(
		variables.environment.APP_BASE_URL ?: "http://localhost:8090",
		"/$",
		""
	);

	boolean function sendEmailVerification( required struct user, required string token ){
		var link = "#variables.baseUrl#/verify-email/#urlEncodedFormat( arguments.token )#";
		var portuguese = arguments.user.locale == "pt_BR";
		return brevoEmailProvider.send(
			recipientEmail = arguments.user.email,
			recipientName = arguments.user.displayName,
			subject = portuguese ? "Confirme seu e-mail no Tabor Lane" : "Confirm your Tabor Lane email",
			htmlContent = emailHtml(
				portuguese ? "Confirme seu e-mail" : "Confirm your email",
				portuguese
					? "Finalize seu cadastro para acessar seu workspace."
					: "Finish setting up your account to access your workspace.",
				portuguese ? "Confirmar e-mail" : "Confirm email",
				link
			),
			textContent = "#portuguese ? 'Confirme seu e-mail' : 'Confirm your email'#: #link#"
		);
	}

	boolean function sendPasswordReset( required struct user, required string token ){
		var link = "#variables.baseUrl#/reset-password/#urlEncodedFormat( arguments.token )#";
		var portuguese = arguments.user.locale == "pt_BR";
		return brevoEmailProvider.send(
			recipientEmail = arguments.user.email,
			recipientName = arguments.user.displayName,
			subject = portuguese ? "Redefina sua senha do Tabor Lane" : "Reset your Tabor Lane password",
			htmlContent = emailHtml(
				portuguese ? "Redefina sua senha" : "Reset your password",
				portuguese
					? "Este link expira em 30 minutos. Ignore esta mensagem se você não fez a solicitação."
					: "This link expires in 30 minutes. Ignore this message if you didn't request it.",
				portuguese ? "Criar nova senha" : "Create new password",
				link
			),
			textContent = "#portuguese ? 'Redefina sua senha' : 'Reset your password'#: #link#"
		);
	}

	boolean function sendWorkspaceInvitation( required struct invitation ){
		var link = "#variables.baseUrl#/invite/#urlEncodedFormat( arguments.invitation.token )#";
		var portuguese = arguments.invitation.locale == "pt_BR";
		return brevoEmailProvider.send(
			recipientEmail = arguments.invitation.email,
			recipientName = arguments.invitation.inviteeName,
			subject = portuguese ? "Convite para o Tabor Lane" : "Your Tabor Lane invitation",
			htmlContent = emailHtml(
				portuguese ? "Você foi convidado" : "You've been invited",
				portuguese
					? "#encodeForHTML( arguments.invitation.inviterName )# convidou você para o workspace #encodeForHTML( arguments.invitation.workspaceName )#."
					: "#encodeForHTML( arguments.invitation.inviterName )# invited you to the #encodeForHTML( arguments.invitation.workspaceName )# workspace.",
				portuguese ? "Aceitar convite" : "Accept invitation",
				link
			),
			textContent = "#portuguese ? 'Aceite o convite' : 'Accept the invitation'#: #link#"
		);
	}

	private string function emailHtml(
		required string heading,
		required string body,
		required string buttonLabel,
		required string link
	){
		return '<!doctype html><html><body style="margin:0;background:##f8f4f1;font-family:Arial,sans-serif;color:##25191b"><div style="max-width:560px;margin:40px auto;padding:36px;background:white;border:1px solid ##eadfe0;border-radius:14px"><strong style="color:##c63d4b">Tabor Lane</strong><h1 style="font-size:26px">#encodeForHTML( arguments.heading )#</h1><p style="color:##6f6265;line-height:1.6">#arguments.body#</p><a href="#encodeForHTMLAttribute( arguments.link )#" style="display:inline-block;margin-top:12px;padding:13px 20px;border-radius:8px;color:white;background:##c63d4b;text-decoration:none;font-weight:bold">#encodeForHTML( arguments.buttonLabel )#</a></div></body></html>';
	}

}
