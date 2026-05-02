import {
  Controller, Post, Body, Headers, HttpCode, HttpStatus,
} from '@nestjs/common';
import { SetMetadata } from '@nestjs/common';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { IS_PUBLIC_KEY } from '../../common/guards/jwt-auth.guard';

const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Public()
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(
    @Body() dto: LoginDto,
    @Headers('x-garage-id') garageId: string,
  ) {
    return this.authService.login(dto, garageId);
  }
}
