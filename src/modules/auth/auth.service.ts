import {
  Injectable,
  UnauthorizedException,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcryptjs';
import { User } from '../users/entities/user.entity';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { UserRole } from '../../common/enums';

interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
}

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
    private readonly jwtService: JwtService,
    private readonly config: ConfigService,
  ) {}

  async register(dto: RegisterDto): Promise<{ user: Partial<User>; tokens: TokenPair }> {
    const exists = await this.userRepo.findOne({
      where: { email: dto.email, garageId: dto.garageId },
    });
    if (exists) throw new ConflictException('Email already registered in this garage');

    const saltRounds = this.config.get<number>('app.bcrypt.saltRounds')!;
    const passwordHash = await bcrypt.hash(dto.password, saltRounds);

    const user = this.userRepo.create({
      garageId: dto.garageId,
      email: dto.email,
      passwordHash,
      fullName: dto.fullName,
      phone: dto.phone ?? null,
      role: dto.role ?? UserRole.TECHNICIAN,
    });

    await this.userRepo.save(user);
    return { user: this.sanitize(user), tokens: this.issueTokens(user) };
  }

  async login(dto: LoginDto, garageId: string): Promise<{ user: Partial<User>; tokens: TokenPair }> {
    const user = await this.userRepo.findOne({
      where: { email: dto.email, garageId, isActive: true },
    });

    if (!user || !(await bcrypt.compare(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('Invalid credentials');
    }

    await this.userRepo.update(user.id, { lastLoginAt: new Date() });
    return { user: this.sanitize(user), tokens: this.issueTokens(user) };
  }

  private issueTokens(user: User): TokenPair {
    const payload = {
      sub: user.id,
      email: user.email,
      role: user.role,
      garageId: user.garageId,
    };

    const expiresIn = this.config.get<string>('app.jwt.expiresIn')!;

    return {
      accessToken: this.jwtService.sign(payload, {
        secret: this.config.get<string>('app.jwt.secret'),
        expiresIn,
      }),
      refreshToken: this.jwtService.sign(
        { sub: user.id, garageId: user.garageId, type: 'refresh' },
        {
          secret: this.config.get<string>('app.jwt.refreshSecret'),
          expiresIn: this.config.get<string>('app.jwt.refreshExpiresIn'),
        },
      ),
      expiresIn,
    };
  }

  private sanitize(user: User): Partial<User> {
    const { passwordHash: _, ...rest } = user;
    return rest;
  }
}
