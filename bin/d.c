#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#define h_addr h_addr_list[0] /* for backward compatibility */

#define check(condition, message) \
  if (condition) { perror(message); exit(1); }


int
create_socket(char *host, int port) {

  int sockfd = socket(AF_INET, SOCK_STREAM, 0);
  check(sockfd < 0, "error opening socket");

  struct hostent *server = gethostbyname(host);
  check(!server, "could not resolve hostname");

  in_addr_t in_addr = inet_addr(
      inet_ntoa(*(struct in_addr*)*(server->h_addr_list)));

  struct sockaddr_in serv_addr;
  serv_addr.sin_addr.s_addr = in_addr;
  serv_addr.sin_family = AF_INET;
  serv_addr.sin_port = htons(port);

  check(
      connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0,
      "error connecting to remote host");

  return sockfd;
}

int
main(int argc, char **argv) {

  // determine length of query, send it
  int t_length = 0;

  for (int i = 1; i < argc; i++) {
    t_length += strlen(argv[i]) + 1;
  }

  int length = htonl(t_length == 0 ? 1 : t_length);
  int sockfd = create_socket("localhost", 9999);
  check(
      write(sockfd, &length, sizeof(length)) < 0,
      "error writing to socket");

  // send all the arguments to the server, deliminated by newlines
  int  buffer_size = 1024;
  char buffer[buffer_size];

  if (argc == 1) {
    memset(buffer, 0, buffer_size);
    snprintf(buffer, buffer_size - 1, "\n");
    check(
        write(sockfd, buffer, strlen(buffer)) < 0,
        "error writing to socket");
  }
  else {
    for (int i = 1; i < argc; i++) {

      memset(buffer, 0, buffer_size);
      snprintf(buffer, buffer_size - 1, "%s\n", argv[i]);
      check(
          write(sockfd, buffer, strlen(buffer)) < 0,
          "error writing to socket");
    }
  }

  // we're done sending data
  shutdown(sockfd, SHUT_WR);
  memset(buffer, 0, buffer_size);

  // read length of the reply, throw it away
  char bytes[4];
  check(read(sockfd, bytes, 4) != 4, "error reading length");

  // receive the response
  while (read(sockfd, buffer, buffer_size - 1) > 0) {

    if (buffer[0] != '\n') {
      printf("%s", buffer);
    }
    memset(buffer, 0, buffer_size);
  }

  return 0;
}
