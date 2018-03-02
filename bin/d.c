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


int create_socket(host, port)
  char *host;
  int   port;
{
  struct sockaddr_in serv_addr;
  struct hostent    *server = gethostbyname(host);

  int sockfd = socket(AF_INET, SOCK_STREAM, 0);
  check(sockfd < 0, "error opening socket");

  memset(&serv_addr, 0, sizeof(serv_addr));

  serv_addr.sin_family = AF_INET;
  memcpy(server->h_addr, &serv_addr.sin_addr.s_addr, server->h_length);

  serv_addr.sin_port = htons(port);
  check(
      connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0,
      "error connecting to remote host");

  return sockfd;
}

int main(argc, argv)
  int    argc;
  char **argv;
{
  int  buffer_size = 1024;
  char buffer[buffer_size];
  int  sockfd = create_socket("localhost", 9999);

  // send all the arguments to the server, deliminated by newlines
  for (int i = 1; i < argc; i++) {

    memset(buffer, 0, buffer_size);
    snprintf(buffer, buffer_size - 1, "%s\n", argv[i]);
    check(
        write(sockfd, buffer, strlen(buffer)) < 0,
        "error writing to socket");
  }

  // we're done sending data
  shutdown(sockfd, SHUT_WR);
  memset(buffer, 0, buffer_size);

  // receive the response
  while (read(sockfd, buffer, buffer_size - 1) > 0) {

    printf("%s", buffer);
    memset(buffer, 0, buffer_size);
  }

  return 0;
}