component {

	function configure(){
		var environment = server.system.environment;
		var processingEnabled = booleanSetting(
			environment.OUTBOX_PROCESSING_ENABLED ?: "true",
			true
		);
		if ( !processingEnabled ) return;

		var batchSize = integerSetting(
			environment.OUTBOX_BATCH_SIZE ?: 50,
			50,
			1,
			500
		);
		var intervalSeconds = integerSetting(
			environment.OUTBOX_INTERVAL_SECONDS ?: 10,
			10,
			1,
			300
		);

		task( "process-events-outbox" )
			.call( function(){
				return getInstance( "OutboxProcessorService" ).processBatch(
					batchSize=batchSize
				);
			} )
			.every( intervalSeconds, "seconds" )
			.withNoOverlaps();
	}

	private boolean function booleanSetting(
		required any value,
		required boolean fallback
	){
		var normalized = lCase( trim( toString( arguments.value ) ) );
		if ( listFindNoCase( "1,true,yes,on", normalized ) ) return true;
		if ( listFindNoCase( "0,false,no,off", normalized ) ) return false;
		return arguments.fallback;
	}

	private numeric function integerSetting(
		required any value,
		required numeric fallback,
		required numeric minimum,
		required numeric maximum
	){
		if ( !isNumeric( arguments.value ) ) return arguments.fallback;
		var parsed = fix( val( arguments.value ) );
		if ( parsed < arguments.minimum || parsed > arguments.maximum ) {
			return arguments.fallback;
		}
		return parsed;
	}

}
