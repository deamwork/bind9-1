#ifndef DNS_TCPMSG_H
#define DNS_TCPMSG_H

#include <isc/buffer.h>

typedef struct {
	unsigned int		magic;
	u_int16_t		size;
	isc_buffer_t		buffer;
	unsigned int		maxsize;
	isc_mem_t	       *mctx;
	isc_socket_t	       *sock;
	isc_task_t	       *task;
	isc_taskaction_t	action;
	void		       *arg;
	dns_result_t		result;
	isc_event_t		event;
} dns_tcpmsg_t;

void
dns_tcpmsg_initialize(isc_mem_t *mctx, isc_socket_t *sock,
		      dns_tcpmsg_t *tcpmsg);
/*
 * Associate a tcp message state with a given memory context and
 * TCP socket.
 *
 * Requires:
 *
 *	"mctx" and "sock" be non-NULL and valid types.
 *
 *	"sock" be a read/write TCP socket.
 *
 *	"tcpmsg" be non-NULL and an uninitialized or invalidated structure.
 *
 * Ensures:
 *
 *	"tcpmsg" is a valid structure.
 */

void
dns_tcpmsg_setmaxsize(dns_tcpmsg_t *tcpmsg, unsigned int maxsize);
/*
 * Set the maximum packet size to "maxsize"
 *
 * Requires:
 *
 *	"tcpmsg" be valid.
 *
 *	512 <= "maxsize" <= 65536
 */

dns_result_t
dns_tcpmsg_readmessage(dns_tcpmsg_t *tcpmsg,
		       isc_task_t *task, isc_taskaction_t action, void *arg);
/*
 * Schedule an event to be delivered when a DNS message is readable, or
 * when an error occurs on the socket.
 *
 * Requires:
 *
 *	"tcpmsg" be valid.
 *
 *	"task", "taskaction", and "arg" be valid.
 *
 * Returns:
 *
 *	ISC_R_SUCCESS		-- no error
 *	Anything that the isc_socket_recv() call can return.  XXXMLG
 *
 * Notes:
 *
 *	The event delivered is a fully generic event.  It will contain no
 *	actual data.  The sender will be a pointer to the dns_tcpmsg_t.
 *	The result code inside that structure should be checked to see
 *	what the final result was.
 */

void
dns_tcpmsg_cancelread(dns_tcpmsg_t *tcpmsg);
/*
 * Cancel a readmessage() call.  The event will still be posted with a
 * CANCELED result code.
 *
 * Requires:
 *
 *	"tcpmsg" be valid.
 */

void
dns_tcpmsg_keepbuffer(dns_tcpmsg_t *tcpmsg, isc_buffer_t *buffer);
/*
 * If a dns buffer is to be kept between calls, this function marks the
 * internal state-machine buffer as invalid, and copyies all the contents
 * of the state into "buffer".
 *
 * Requires:
 *
 *	"tcpmsg" be valid.
 *
 *	"buffer" be non-NULL.
 */

void
dns_tcpmsg_invalidate(dns_tcpmsg_t *tcpmsg);
/*
 * Clean up all allocated state, and invalidate the structure.
 *
 * Requires:
 *
 *	"tcpmsg" be valid.
 *
 * Ensures:
 *
 *	"tcpmsg" is invalidated and disassociated with all memory contexts,
 *	sockets, etc.
 */

#endif /* DNS_TCPMSG_H */
