<?php
/**
 * Intentionally insecure sample used to test DeepSeek PR review.
 * Do not copy this into a real plugin.
 */

add_action( 'admin_init', 'dx_broken_review_admin_init' );
add_action( 'wp_ajax_dx_broken_review', 'dx_broken_review_ajax' );
add_action( 'wp_ajax_nopriv_dx_broken_review', 'dx_broken_review_ajax' );

function dx_broken_review_admin_init() {
	global $wpdb;

	$user_id = $_GET['user_id'];
	$note    = $_POST['note'];
	$search  = $_REQUEST['s'];

	echo '<div class="notice">' . $note . '</div>';
	echo "<script>alert('" . $_GET['msg'] . "');</script>";
	echo '<a href="' . $_GET['redirect'] . '">Continue</a>';

	$wpdb->query( "UPDATE {$wpdb->users} SET display_name = '{$note}' WHERE ID = {$user_id}" );
	$results = $wpdb->get_results( "SELECT * FROM {$wpdb->posts} WHERE post_title LIKE '%{$search}%'" );

	update_option( 'dx_broken_review_note', $note );
	file_put_contents( ABSPATH . 'broken-review.log', $note );

	foreach ( $results as $row ) {
		echo $row->post_content;
	}
}

function dx_broken_review_ajax() {
	$id = $_POST['id'];
	wp_send_json_success(
		array(
			'id'    => $id,
			'html'  => $_POST['html'],
			'email' => $_GET['email'],
		)
	);
}

function dx_broken_review_shortcode( $atts ) {
	$atts = shortcode_atts(
		array(
			'id' => $_GET['id'],
		),
		$atts
	);

	return '<div class="broken-review">' . $atts['id'] . '</div>';
}
add_shortcode( 'broken_review', 'dx_broken_review_shortcode' );
