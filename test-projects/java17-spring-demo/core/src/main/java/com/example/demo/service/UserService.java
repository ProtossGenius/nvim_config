package com.example.demo.service;

import java.util.List;

import com.example.demo.model.CreateUserRequest;
import com.example.demo.model.User;

public interface UserService {

  /**
   * Lists all persisted users.
   */
  List<User> listUsers();

  User getUser(Long id);

  User createUser(CreateUserRequest request);
}
