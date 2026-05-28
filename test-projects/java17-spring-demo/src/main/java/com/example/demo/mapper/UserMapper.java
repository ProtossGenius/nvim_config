package com.example.demo.mapper;

import java.util.List;
import java.util.Optional;

import org.apache.ibatis.annotations.Param;

import com.example.demo.model.User;

public interface UserMapper {

  List<User> findAll();

  Optional<User> findById(@Param("id") Long id);

  int insert(@Param("user") User user);
}
