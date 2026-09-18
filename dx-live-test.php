<?php
/**
 * Live test fixture for DX Code Review Bot. Intentionally insecure.
 */

add_action( 'wp_ajax_nopriv_dx_live_test', 'dx_live_test_ajax' );

function dx_live_test_ajax() {
	echo $_GET['msg'];
	$wpdb = $GLOBALS['wpdb'];
	$wpdb->query( "DELETE FROM {$wpdb->users} WHERE ID = {$_POST['id']}" );
	file_put_contents( ABSPATH . 'dx-live-test.log', $_POST['note'] );
	wp_send_json_success( $_POST['html'] );
}
