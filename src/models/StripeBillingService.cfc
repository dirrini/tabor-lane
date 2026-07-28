component singleton {

	variables.environment = server.system.environment;
	variables.secretKey = variables.environment.STRIPE_SECRET_KEY ?: "";
	variables.webhookSecret = variables.environment.STRIPE_WEBHOOK_SECRET ?: "";
	variables.monthlyPriceId = variables.environment.STRIPE_PRICE_PREMIUM_MONTHLY ?: "";
	variables.yearlyPriceId = variables.environment.STRIPE_PRICE_PREMIUM_YEARLY ?: "";
	variables.baseUrl = reReplace( variables.environment.APP_BASE_URL ?: "http://localhost:8090", "/$", "" );

	boolean function isConfigured(){
		return variables.secretKey.len() > 0
			&& variables.monthlyPriceId.len() > 0
			&& variables.yearlyPriceId.len() > 0;
	}

	struct function getBilling( required string userId, required string workspaceId ){
		var rows = queryExecute(
			"SELECT w.plan, wm.role, wb.stripe_customer_id, wb.stripe_subscription_id,
			        COALESCE(wb.subscription_status, 'none') AS subscription_status,
			        wb.billing_interval, wb.current_period_end, wb.cancel_at_period_end
			 FROM workspace_member wm
			 JOIN workspace w ON w.id = wm.workspace_id
			 LEFT JOIN workspace_billing wb ON wb.workspace_id = w.id
			 WHERE wm.user_id = CAST(:userId AS UUID)
			   AND wm.workspace_id = CAST(:workspaceId AS UUID)",
			{ userId = arguments.userId, workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		if ( !rows.len() ) {
			return { found = false };
		}
		return {
			found = true,
			plan = rows[ 1 ].plan,
			role = rows[ 1 ].role,
			customerId = rows[ 1 ].stripe_customer_id ?: "",
			subscriptionId = rows[ 1 ].stripe_subscription_id ?: "",
			status = rows[ 1 ].subscription_status,
			interval = rows[ 1 ].billing_interval ?: "",
			currentPeriodEnd = rows[ 1 ].current_period_end ?: "",
			cancelAtPeriodEnd = rows[ 1 ].cancel_at_period_end ?: false,
			canManage = rows[ 1 ].role == "owner",
			configured = isConfigured()
		};
	}

	struct function createCheckout(
		required string userId,
		required string workspaceId,
		required string email,
		required string interval
	){
		if ( !isConfigured() || !listFindNoCase( "monthly,yearly", arguments.interval ) ) {
			return { success = false, code = "not_configured" };
		}
		var billing = getBilling( arguments.userId, arguments.workspaceId );
		if ( !billing.found || !billing.canManage ) {
			return { success = false, code = "forbidden" };
		}
		if ( billing.subscriptionId.len() && listFindNoCase( "active,trialing,past_due", billing.status ) ) {
			return { success = false, code = "already_subscribed" };
		}
		var memberCount = queryExecute(
			"SELECT COUNT(*) AS total FROM workspace_member
			 WHERE workspace_id = CAST(:workspaceId AS UUID)",
			{ workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		)[ 1 ].total;
		var priceId = arguments.interval == "yearly" ? variables.yearlyPriceId : variables.monthlyPriceId;
		var fields = {
			"mode" = "subscription",
			"line_items[0][price]" = priceId,
			"line_items[0][quantity]" = max( 1, memberCount ),
			"client_reference_id" = arguments.workspaceId,
			"metadata[workspace_id]" = arguments.workspaceId,
			"metadata[billing_interval]" = arguments.interval,
			"subscription_data[metadata][workspace_id]" = arguments.workspaceId,
			"subscription_data[metadata][billing_interval]" = arguments.interval,
			"success_url" = "#variables.baseUrl#/app/billing?checkout=success",
			"cancel_url" = "#variables.baseUrl#/app/billing?checkout=cancelled",
			"allow_promotion_codes" = "true"
		};
		if ( billing.customerId.len() ) {
			fields[ "customer" ] = billing.customerId;
		} else {
			fields[ "customer_email" ] = lCase( trim( arguments.email ) );
		}
		var response = stripePost( "/v1/checkout/sessions", fields );
		return response.success && ( response.data.url ?: "" ).len()
			? { success = true, url = response.data.url }
			: { success = false, code = "stripe_error" };
	}

	struct function createPortal( required string userId, required string workspaceId ){
		var billing = getBilling( arguments.userId, arguments.workspaceId );
		if ( !billing.found || !billing.canManage ) {
			return { success = false, code = "forbidden" };
		}
		if ( !variables.secretKey.len() || !billing.customerId.len() ) {
			return { success = false, code = "not_available" };
		}
		var response = stripePost(
			"/v1/billing_portal/sessions",
			{ customer = billing.customerId, return_url = "#variables.baseUrl#/app/billing" }
		);
		return response.success && ( response.data.url ?: "" ).len()
			? { success = true, url = response.data.url }
			: { success = false, code = "stripe_error" };
	}

	struct function processWebhook( required string payload, required string signature ){
		if ( !verifySignature( arguments.payload, arguments.signature ) ) {
			return { success = false, code = "invalid_signature" };
		}
		try {
			var stripeEvent = deserializeJSON( arguments.payload );
			if ( !( stripeEvent.id ?: "" ).len() || !( stripeEvent.type ?: "" ).len() ) {
				return { success = false, code = "invalid_event" };
			}
			var eventObject = stripeEvent.data.object ?: {};
			transaction {
				var inserted = queryExecute(
					"INSERT INTO stripe_webhook_event (stripe_event_id, event_type)
					 VALUES (:eventId, :eventType)
					 ON CONFLICT (stripe_event_id) DO NOTHING
					 RETURNING stripe_event_id",
					{ eventId = stripeEvent.id, eventType = stripeEvent.type },
					{ returntype = "array" }
				);
				if ( !inserted.len() ) {
					return { success = true, duplicate = true };
				}
				if ( stripeEvent.type == "checkout.session.completed" ) {
					syncCheckoutSession( eventObject );
				} else if (
					listFindNoCase(
						"customer.subscription.created,customer.subscription.updated,customer.subscription.deleted",
						stripeEvent.type
					)
				) {
					syncSubscription( eventObject, stripeEvent.type );
				}
			}
			return { success = true };
		} catch ( any exception ) {
			writeLog(
				file = "application",
				type = "error",
				text = "Stripe webhook processing failed: #exception.message#"
			);
			return { success = false, code = "processing_failed" };
		}
	}

	private void function syncCheckoutSession( required struct sessionData ){
		var workspaceId = sessionData.metadata.workspace_id ?: sessionData.client_reference_id ?: "";
		if ( !workspaceId.len() ) {
			return;
		}
		queryExecute(
			"INSERT INTO workspace_billing
			    (workspace_id, stripe_customer_id, stripe_subscription_id, subscription_status, billing_interval)
			 VALUES
			    (CAST(:workspaceId AS UUID), :customerId, :subscriptionId, 'checkout_complete', :billingInterval)
			 ON CONFLICT (workspace_id) DO UPDATE SET
			    stripe_customer_id = COALESCE(EXCLUDED.stripe_customer_id, workspace_billing.stripe_customer_id),
			    stripe_subscription_id = COALESCE(EXCLUDED.stripe_subscription_id, workspace_billing.stripe_subscription_id),
			    billing_interval = COALESCE(EXCLUDED.billing_interval, workspace_billing.billing_interval),
			    updated_at = now()",
			{
				workspaceId = workspaceId,
				customerId = nullableText( sessionData.customer ?: "" ),
				subscriptionId = nullableText( sessionData.subscription ?: "" ),
				billingInterval = nullableText( sessionData.metadata.billing_interval ?: "" )
			}
		);
		if ( listFindNoCase( "paid,no_payment_required", sessionData.payment_status ?: "" ) ) {
			queryExecute(
				"UPDATE workspace SET plan = 'premium', updated_at = now()
				 WHERE id = CAST(:workspaceId AS UUID)",
				{ workspaceId = workspaceId }
			);
		}
	}

	private void function syncSubscription( required struct subscription, required string eventType ){
		var workspaceId = subscription.metadata.workspace_id ?: "";
		if ( !workspaceId.len() ) {
			return;
		}
		var status = arguments.eventType == "customer.subscription.deleted"
			? "canceled"
			: subscription.status ?: "unknown";
		var priceId = "";
		if ( ( subscription.items.data ?: [] ).len() ) {
			priceId = subscription.items.data[ 1 ].price.id ?: "";
		}
		var interval = subscription.metadata.billing_interval ?: "";
		if ( !interval.len() && ( subscription.items.data ?: [] ).len() ) {
			interval = subscription.items.data[ 1 ].price.recurring.interval ?: "";
		}
		var premium = listFindNoCase( "active,trialing,past_due", status ) > 0;
		var periodEnd = subscription.current_period_end ?: 0;
		if ( !periodEnd && ( subscription.items.data ?: [] ).len() ) {
			periodEnd = subscription.items.data[ 1 ].current_period_end ?: 0;
		}
		queryExecute(
			"INSERT INTO workspace_billing
			    (workspace_id, stripe_customer_id, stripe_subscription_id, stripe_price_id,
			     subscription_status, billing_interval, current_period_end, cancel_at_period_end)
			 VALUES
			    (CAST(:workspaceId AS UUID), :customerId, :subscriptionId, :priceId,
			     :status, :billingInterval, :periodEnd, :cancelAtPeriodEnd)
			 ON CONFLICT (workspace_id) DO UPDATE SET
			    stripe_customer_id = EXCLUDED.stripe_customer_id,
			    stripe_subscription_id = EXCLUDED.stripe_subscription_id,
			    stripe_price_id = EXCLUDED.stripe_price_id,
			    subscription_status = EXCLUDED.subscription_status,
			    billing_interval = EXCLUDED.billing_interval,
			    current_period_end = EXCLUDED.current_period_end,
			    cancel_at_period_end = EXCLUDED.cancel_at_period_end,
			    updated_at = now()",
			{
				workspaceId = workspaceId,
				customerId = nullableText( subscription.customer ?: "" ),
				subscriptionId = nullableText( subscription.id ?: "" ),
				priceId = nullableText( priceId ),
				status = status,
				billingInterval = nullableText( interval ),
				periodEnd = nullableTimestamp( periodEnd ),
				cancelAtPeriodEnd = subscription.cancel_at_period_end ?: false
			}
		);
		queryExecute(
			"UPDATE workspace SET plan = :plan, updated_at = now()
			 WHERE id = CAST(:workspaceId AS UUID)",
			{ workspaceId = workspaceId, plan = premium ? "premium" : "free" }
		);
	}

	private struct function stripePost( required string path, required struct fields ){
		try {
			var response = {};
			cfhttp(
				method = "POST",
				url = "https://api.stripe.com#arguments.path#",
				result = "response",
				timeout = 15
			) {
				cfhttpparam( type = "header", name = "Authorization", value = "Bearer #variables.secretKey#" );
				for ( var fieldName in arguments.fields ) {
					cfhttpparam(
						type = "formfield",
						name = fieldName,
						value = arguments.fields[ fieldName ]
					);
				}
			}
			var status = val( response.statusCode ?: 0 );
			var data = deserializeJSON( response.fileContent ?: "{}" );
			if ( status >= 200 && status < 300 ) {
				return { success = true, data = data };
			}
			writeLog(
				file = "application",
				type = "error",
				text = "Stripe API rejected request. Status: #status#; type: #data.error.type ?: 'unknown'#; code: #data.error.code ?: 'unknown'#; message: #data.error.message ?: 'No message'#"
			);
			return { success = false, status = status, data = data };
		} catch ( any exception ) {
			writeLog( file = "application", type = "error", text = "Stripe API request failed: #exception.message#" );
			return { success = false };
		}
	}

	private boolean function verifySignature( required string payload, required string signature ){
		if ( !variables.webhookSecret.len() || !arguments.signature.len() ) {
			return false;
		}
		var timestamp = "";
		var signatures = [];
		for ( var part in listToArray( arguments.signature ) ) {
			var separator = find( "=", part );
			if ( separator > 1 ) {
				var key = trim( left( part, separator - 1 ) );
				var value = trim( mid( part, separator + 1 ) );
				if ( key == "t" ) timestamp = value;
				if ( key == "v1" ) signatures.append( lCase( value ) );
			}
		}
		if (
			!timestamp.len()
			|| !signatures.len()
			|| abs( createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000 - val( timestamp ) ) > 300
		) {
			return false;
		}
		var expected = lCase( hmac( "#timestamp#.#arguments.payload#", variables.webhookSecret, "HmacSHA256" ) );
		for ( var candidate in signatures ) {
			if ( constantTimeEquals( expected, candidate ) ) return true;
		}
		return false;
	}

	private boolean function constantTimeEquals( required string first, required string second ){
		if ( arguments.first.len() != arguments.second.len() ) return false;
		var difference = 0;
		for ( var index = 1; index <= arguments.first.len(); index++ ) {
			difference = bitOr(
				difference,
				bitXor( asc( mid( arguments.first, index, 1 ) ), asc( mid( arguments.second, index, 1 ) ) )
			);
		}
		return difference == 0;
	}

	private struct function nullableText( required string value ){
		return { value = arguments.value, null = !arguments.value.len(), sqltype = "varchar" };
	}

	private struct function nullableTimestamp( required numeric epoch ){
		return {
			value = arguments.epoch > 0 ? createObject( "java", "java.util.Date" ).init( javacast( "long", arguments.epoch * 1000 ) ) : "",
			null = arguments.epoch <= 0,
			sqltype = "timestamp"
		};
	}

}
